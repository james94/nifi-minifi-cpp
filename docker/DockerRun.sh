#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: ./DockerRun.sh [options]"
  echo "Options:"
  echo "  -i, --image                 Docker image (e.g., apacheminificpp:1.25.0)"
  echo "  -p, --prefix                Image tag prefix used by build (e.g., minimal)"
  echo "  -d, --distro-name           Distro tag segment used by build (centos|rockylinux)"
  echo "  -v, --version               MiNiFi version used by build (e.g., 1.25.0)"
  echo "  -b, --build-number          Optional build number used by build (e.g., 42)"
  echo "  -n, --name                  Container name override"
  echo "  -N, --network               Docker network (default: fleet-net)"
  echo "  -r, --root                  Host persistence root (default: /home/ubuntu/src/james/nifi-minifi-cpp/minifi-data)"
  echo "  -c, --conf                  Host conf dir (default: /home/ubuntu/src/james/nifi-minifi-cpp/conf)"
  echo "  -P, --port                  Extra port mapping (host:container), repeatable"
  echo "  -H, --http-port             Map extension HTTP port (e.g., 8081)"
  echo "  -E, --env                   Extra env NAME=VALUE (repeatable)"
  echo "  -f, --flow-config           Host path to MiNiFi flow config.yml to mount read-only"
  echo "  -m, --properties            Host path to MiNiFi minifi.properties to mount read-only"
  echo "  --nifi-host                 NiFi hostname for preflight check (e.g., nifi-2.6.0)"
  echo "  --nifi-port                 NiFi web port for preflight check (default: 8080)"
  echo "  -Z, --privileged           Run container with --privileged (optional)"
  echo "  -h, --help                  Show help"
  exit 0
}

# Defaults
DOCKER_IMAGE="${DOCKER_IMAGE:-}"      # empty -> compute or discover via 'docker images'
PREFIX="${PREFIX:-}"
DISTRO_NAME="${DISTRO_NAME:-}"
MINIFI_VERSION="${MINIFI_VERSION:-}"
BUILD_NUMBER_ARG="${BUILD_NUMBER_ARG:-}"
CONTAINER_NAME="${CONTAINER_NAME:-minifi-cpp}"
DOCKER_NETWORK="${DOCKER_NETWORK:-fleet-net}"
ROOT="${ROOT:-/home/ubuntu/src/james/nifi-minifi-cpp/minifi-data}"
CONF_DIR="${CONF_DIR:-/home/ubuntu/src/james/nifi-minifi-cpp/conf}"
LOG_DIR="${LOG_DIR:-${ROOT}/logs}"
FLOWFILE_DIR="${FLOWFILE_DIR:-${ROOT}/flowfile_repository}"
CONTENT_DIR="${CONTENT_DIR:-${ROOT}/content_repository}"
PROVENANCE_DIR="${PROVENANCE_DIR:-${ROOT}/provenance_repository}"
MINIFI_HTTP_PORT="${MINIFI_HTTP_PORT:-}"
EXTRA_ENVS=()
EXTRA_PORTS=()
FLOW_CONFIG_PATH="${FLOW_CONFIG_PATH:-}"
PROPERTIES_PATH="${PROPERTIES_PATH:-}"
NIFI_PREFLIGHT_HOST="${NIFI_PREFLIGHT_HOST:-}"
NIFI_PREFLIGHT_PORT="${NIFI_PREFLIGHT_PORT:-8080}"
NIFI_S2S_RAW_HOST_PORT=""   # host-mapped RAW port if published
DATA_DIR="${ROOT}"
PRIVILEGED=0
RUN_OPTS=()  # collect extra docker run options safely under 'set -u'

# Parse args (align with DockerBuild.sh semantics)
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--image) DOCKER_IMAGE="$2"; shift 2 ;;
    -p|--prefix) PREFIX="$2"; shift 2 ;;
    -d|--distro-name) DISTRO_NAME="$2"; shift 2 ;;
    -v|--version) MINIFI_VERSION="$2"; shift 2 ;;
    -b|--build-number) BUILD_NUMBER_ARG="$2"; shift 2 ;;
    -n|--name) CONTAINER_NAME="$2"; shift 2 ;;
    -N|--network) DOCKER_NETWORK="$2"; shift 2 ;;
    -r|--root) ROOT="$2"; LOG_DIR="${ROOT}/logs"; FLOWFILE_DIR="${ROOT}/flowfile_repository"; CONTENT_DIR="${ROOT}/content_repository"; PROVENANCE_DIR="${ROOT}/provenance_repository"; shift 2 ;;
    -c|--conf) CONF_DIR="$2"; shift 2 ;;
    -H|--http-port) MINIFI_HTTP_PORT="$2"; shift 2 ;;
    -P|--port) EXTRA_PORTS+=("$2"); shift 2 ;;
    -E|--env) EXTRA_ENVS+=("$2"); shift 2 ;;
    -f|--flow-config) FLOW_CONFIG_PATH="$2"; shift 2 ;;
    -m|--properties)  PROPERTIES_PATH="$2"; shift 2 ;;
    --nifi-host)      NIFI_PREFLIGHT_HOST="$2"; shift 2 ;;
    --nifi-port)      NIFI_PREFLIGHT_PORT="$2"; shift 2 ;;
    -Z|--privileged) PRIVILEGED=1; shift 1 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

# Validate optional files if provided
if [[ -n "${FLOW_CONFIG_PATH}" && ! -f "${FLOW_CONFIG_PATH}" ]]; then
  echo "Flow config not found: ${FLOW_CONFIG_PATH}"; exit 1
fi
if [[ -n "${PROPERTIES_PATH}" && ! -f "${PROPERTIES_PATH}" ]]; then
  echo "Properties file not found: ${PROPERTIES_PATH}"; exit 1
fi

# NOTE: From outside the MiNiFi C++ Docker container, NiFi S2S reachable using localhost
# For HTTP Site To Site and TCP Site to Site: check_nifi_s2s(), check_nifi_raw_s2s()

# Optional NiFi preflight check (detect HTTP 500 early)
check_nifi_s2s() {
  # HTTP Site-to-Site API preflight
  local host="$1" port="$2"
  local url="http://127.0.0.1:${port}/nifi-api/site-to-site"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' "${url}" || true)"
  if [[ "${code}" != "200" ]]; then
    echo "Warning: NiFi S2S endpoint ${url} returned HTTP ${code}. MiNiFi may not connect. Ensure NiFi is healthy and unsecured (AUTH unset)."
  else
    echo "Preflight: NiFi S2S (HTTP) reachable at ${url} (HTTP ${code})"
  fi
}

tcp_open() {
  # Try bash /dev/tcp first, fallback to nc if available
  local host="$1" port="$2"
  if timeout 2 bash -c ">& /dev/tcp/${host}/${port}" 2>/dev/null; then
    return 0
  elif command -v nc >/dev/null 2>&1; then
    nc -z -w 2 "${host}" "${port}" >/dev/null 2>&1 && return 0
  fi
  return 1
}

check_nifi_raw_s2s() {
  # RAW Site-to-Site TCP preflight (10000/tcp)
  local cname="$1"
  local preferred_host="${2:-$cname}"

  # If 10000/tcp is published to the host, test that mapping; else print network heads-up
  if docker port "${cname}" 10000/tcp >/dev/null 2>&1; then
    NIFI_S2S_RAW_HOST_PORT="$(docker port "${cname}" 10000/tcp | awk -F: '{print $NF}' | head -n1)"
    local host_port="${NIFI_S2S_RAW_HOST_PORT:-10000}"
    if tcp_open "127.0.0.1" "${host_port}"; then
      echo "Preflight: NiFi RAW S2S open on localhost:${host_port}"
    else
      echo "Warning: NiFi RAW S2S not reachable on localhost:${host_port}. Check firewall or port mapping."
    fi
  else
    echo "Heads-up: NiFi RAW S2S (10000/tcp) is not published to the host. MiNiFi will connect over Docker network '${DOCKER_NETWORK}' to '${preferred_host}:10000'."
  fi
}

autodetect_nifi_prefs() {
  # Find a running NiFi container (exclude NiFi Registry)
  local cname
  cname="$(docker ps --format '{{.Names}}' | grep -i 'nifi' | grep -vi 'registry' | head -n1 || true)"
  if [[ -z "${cname}" ]]; then
    return 0
  fi

  # Prefer 8080, then 8443 for web preflight
  local host_port=""
  if docker port "${cname}" 8080/tcp >/dev/null 2>&1; then
    host_port="$(docker port "${cname}" 8080/tcp | awk -F: '{print $NF}' | head -n1)"
    [[ -z "${host_port}" ]] && host_port="8080"
    NIFI_PREFLIGHT_PORT="${NIFI_PREFLIGHT_PORT:-${host_port}}"
  elif docker port "${cname}" 8443/tcp >/dev/null 2>&1; then
    host_port="$(docker port "${cname}" 8443/tcp | awk -F: '{print $NF}' | head -n1)"
    [[ -z "${host_port}" ]] && host_port="8443"
    NIFI_PREFLIGHT_PORT="${NIFI_PREFLIGHT_PORT:-${host_port}}"
  else
    NIFI_PREFLIGHT_PORT="${NIFI_PREFLIGHT_PORT:-8080}"
  fi

  # Use container name as hostname on the shared Docker network
  NIFI_PREFLIGHT_HOST="${NIFI_PREFLIGHT_HOST:-${cname}}"

  # RAW S2S preflight
  check_nifi_raw_s2s "${cname}" "${NIFI_PREFLIGHT_HOST}"
}

# If user did not pass host/port, try to autodetect from Docker
if [[ -z "${NIFI_PREFLIGHT_HOST}" ]]; then
  autodetect_nifi_prefs || true
fi

# Run HTTP preflight when we have a host (either provided or autodetected)
if [[ -n "${NIFI_PREFLIGHT_HOST}" ]]; then
  check_nifi_s2s "${NIFI_PREFLIGHT_HOST}" "${NIFI_PREFLIGHT_PORT}"
fi

# Helper: check if an image exists locally
image_exists() {
  local img="$1"
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -Fx "${img}" >/dev/null 2>&1
}

# Helper: discover a suitable minifi image from local docker images
discover_minifi_image() {
  # Prefer apacheminificpp first, then any repo containing 'minifi' with a non-<none> tag
  local found=""
  found="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^apacheminificpp:' | grep -v ':<none>' | head -n1 || true)"
  if [[ -z "${found}" ]]; then
    found="$(docker images --format '{{.Repository}}:{{.Tag}}' | awk '$2!="<none>"{print $1 ":" $2}' | grep -i 'minifi' | head -n1 || true)"
  fi
  echo "${found}"
}

# Compute local tag if not explicitly set
if [[ -z "${DOCKER_IMAGE}" ]]; then
  if [[ -n "${MINIFI_VERSION}" ]]; then
    candidate="apacheminificpp:"
    [[ -n "${PREFIX}" ]] && candidate+="${PREFIX}-"
    [[ -n "${DISTRO_NAME}" ]] && candidate+="${DISTRO_NAME}-"
    candidate+="${MINIFI_VERSION}"
    [[ -n "${BUILD_NUMBER_ARG}" ]] && candidate+="-${BUILD_NUMBER_ARG}"
    if image_exists "${candidate}"; then
      DOCKER_IMAGE="${candidate}"
    else
      # Try to discover any built MiNiFi image locally
      discovered="$(discover_minifi_image)"
      if [[ -n "${discovered}" ]]; then
        DOCKER_IMAGE="${discovered}"
      else
        DOCKER_IMAGE="apache/nifi-minifi-cpp:latest"
      fi
    fi
  else
    # No version provided; discover or fallback to official latest
    discovered="$(discover_minifi_image)"
    DOCKER_IMAGE="${discovered:-apache/nifi-minifi-cpp:latest}"
  fi
fi

# Ensure network and create dirs
if ! docker network inspect "${DOCKER_NETWORK}" >/dev/null 2>&1; then
  echo "Creating network: ${DOCKER_NETWORK}"
  docker network create "${DOCKER_NETWORK}"
fi

mkdir -p "${LOG_DIR}" "${FLOWFILE_DIR}" "${CONTENT_DIR}" "${PROVENANCE_DIR}"

# Ports
PORT_ARGS=()
if [ -n "${MINIFI_HTTP_PORT}" ]; then
  PORT_ARGS+=(-p "${MINIFI_HTTP_PORT}:${MINIFI_HTTP_PORT}")
fi
for mp in "${EXTRA_PORTS[@]}"; do
  PORT_ARGS+=(-p "${mp}")
done

# Volumes
VOLUME_ARGS=(
  -v "${DATA_DIR}:/opt/minifi/minifi-current/data:rw"
  -v "${LOG_DIR}:/opt/minifi/minifi-current/logs:rw"
  -v "${FLOWFILE_DIR}:/opt/minifi/minifi-current/flowfile_repository:rw"
  -v "${CONTENT_DIR}:/opt/minifi/minifi-current/content_repository:rw"
  -v "${PROVENANCE_DIR}:/opt/minifi/minifi-current/provenance_repository:rw"
)
# Prefer file mounts over full conf dir
if [[ -n "${FLOW_CONFIG_PATH}" || -n "${PROPERTIES_PATH}" ]]; then
  [[ -n "${FLOW_CONFIG_PATH}" ]] && VOLUME_ARGS+=(-v "${FLOW_CONFIG_PATH}:/opt/minifi/minifi-current/conf/config.yml:ro")
  [[ -n "${PROPERTIES_PATH}" ]] && VOLUME_ARGS+=(-v "${PROPERTIES_PATH}:/opt/minifi/minifi-current/conf/minifi.properties:ro")
fi

# Extra envs
ENV_ARGS=()
for kv in "${EXTRA_ENVS[@]}"; do
  ENV_ARGS+=(-e "${kv}")
done

# Remove existing container if present
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Removing existing container: ${CONTAINER_NAME}"
  docker rm -f "${CONTAINER_NAME}" >/dev/null
fi


echo "Running MiNiFi C++:"
echo "  Image:    ${DOCKER_IMAGE}"
echo "  Name:     ${CONTAINER_NAME}"
echo "  Network:  ${DOCKER_NETWORK}"
if [[ -n "${PREFIX}${DISTRO_NAME}${MINIFI_VERSION}${BUILD_NUMBER_ARG}" ]]; then
  echo "  Tag from build params: prefix='${PREFIX}' distro='${DISTRO_NAME}' version='${MINIFI_VERSION}' build='${BUILD_NUMBER_ARG}'"
fi
echo "  Volumes:"
if [[ -n "${FLOW_CONFIG_PATH}" || -n "${PROPERTIES_PATH}" ]]; then
  [[ -n "${FLOW_CONFIG_PATH}" ]] && printf "    flow config (ro)     -> %s\n" "${FLOW_CONFIG_PATH}"
  [[ -n "${PROPERTIES_PATH}" ]] && printf "    properties (ro)      -> %s\n" "${PROPERTIES_PATH}"
fi
printf "    data                -> %s\n" "${DATA_DIR}"
printf "    logs                -> %s\n" "${LOG_DIR}"
printf "    flowfile_repository -> %s\n" "${FLOWFILE_DIR}"
printf "    content_repository  -> %s\n" "${CONTENT_DIR}"
printf "    provenance_repo     -> %s\n" "${PROVENANCE_DIR}"
if [ -n "${MINIFI_HTTP_PORT}" ]; then
  echo "  Ports:    HTTP service (extensions) -> ${MINIFI_HTTP_PORT}"
else
  echo "  Ports:    none (MiNiFi has no UI by default)"
fi
echo "Heads-up:"
echo "  - NiFi RAW S2S expected at ${NIFI_PREFLIGHT_HOST:-nifi}:10000 over Docker network '${DOCKER_NETWORK}'."
echo "  - Ensure NiFi has nifi.remote.input.secure=false for unsecured RAW (set by NiFi start.sh when AUTH is unset)."
echo "  - If NiFi is secured (HTTPS/8443), configure MiNiFi TLS client properties in minifi.properties."

# Build docker run options from flags
if [[ "${PRIVILEGED}" -eq 1 ]]; then
  echo "  - Running in privileged mode."
  RUN_OPTS+=(--privileged)
fi


docker run -d --name "${CONTAINER_NAME}" \
  --network "${DOCKER_NETWORK}" \
  "${RUN_OPTS[@]}" \
  "${PORT_ARGS[@]}" \
  "${VOLUME_ARGS[@]}" \
  "${ENV_ARGS[@]}" \
  "${DOCKER_IMAGE}"

echo "MiNiFi C++ started. Config directory mounted at: ${CONF_DIR}"
if [ -n "${NIFI_PREFLIGHT_HOST}" ]; then
  echo "Hint: Set Remote Processing Group target to ${NIFI_PREFLIGHT_HOST}:10000 for RAW S2S in config.yml"
else
  echo "Hint: Ensure your config.yml Remote Processing Group points to your NiFi host:10000"
fi
