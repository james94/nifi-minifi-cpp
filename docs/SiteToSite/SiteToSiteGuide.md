Bidirectional Site-to-Site (S2S) setup between Apache NiFi and a MiNiFi C++ Edge Agent

Overview
- Goal: Enable RAW TCP S2S in both directions on a shared Docker network, using the provided NiFi flow (BiSiteToSiteNiFiAndMiNiFi.json) and MiNiFi YAML (bi_s2s_config.yml).
- Outcome: MiNiFi sends files to NiFi via an RPG Input Port; NiFi sends small messages to MiNiFi via an RPG Output Port, stored by MiNiFi PutFile.

Prerequisites
- Docker and a shared network (fleet-net).
- Images and scripts in:
  - NiFi: /home/ubuntu/src/james/nifi/nifi-docker/dockerhub
  - NiFi Registry: /home/ubuntu/src/james/nifi/nifi-registry/nifi-registry-core/nifi-registry-docker/dockerhub
  - MiNiFi C++: /home/ubuntu/src/james/nifi-minifi-cpp/docker
- RAW S2S port 10000 exposed or reachable over the Docker network.

1) Create shared Docker network
- docker network create fleet-net

2) Build and run NiFi Registry (optional, for flow storage)
- cd /home/ubuntu/src/james/nifi/nifi-registry/nifi-registry-core/nifi-registry-docker/dockerhub
- ./DockerBuild.sh
- ./DockerRun.sh
Notes
- Default container name: nifi-registry
- UI: http://nifi-registry:18080/nifi-registry (or https on 18443 when AUTH=tls)

3) Build and run NiFi
- cd /home/ubuntu/src/james/nifi/nifi-docker/dockerhub
- ./DockerBuild.sh
- ./DockerRun.sh
Key behavior from start.sh and secure.sh
- AUTH unset -> unsecured HTTP UI on 8080 and unsecured S2S (nifi.remote.input.secure=false)
- AUTH=tls -> HTTPS UI on 8443 and secure S2S; requires env variables:
  - KEYSTORE_PATH, KEYSTORE_TYPE, KEYSTORE_PASSWORD
  - TRUSTSTORE_PATH, TRUSTSTORE_TYPE, TRUSTSTORE_PASSWORD
Important NiFi properties applied by scripts
- nifi.remote.input.host set to the container name (NIFI_HOST, default: nifi)
- nifi.remote.input.socket.port set to NIFI_REMOTE_INPUT_SOCKET_PORT (default: 10000)
- Autoload directories for nar_extensions and python_extensions are mounted

4) Import and enable the NiFi flow
- In the NiFi UI, import /home/ubuntu/src/james/nifi-minifi-cpp/docs/SiteToSite/nifi_flow/BiSiteToSiteNiFiAndMiNiFi.json
- Enable:
  - Input Port: FromMiNiFiAgent1 (allow remote access)
  - Output Port: ToMiNiFiAgent1 (allow remote access)
- Verify instance identifiers (from the imported flow):
  - FromMiNiFiAgent1 instanceIdentifier: fbe5c098-019b-1000-f414-3bd10079fcd5
  - ToMiNiFiAgent1 instanceIdentifier: fbe5f8e5-019b-1000-0677-e8133da42b41
These IDs must match the MiNiFi YAML connection source/destination ids.

5) Build the MiNiFi C++ Edge Agent image
- cd /home/ubuntu/src/james/nifi-minifi-cpp/docker
- ./DockerBuild.sh -v 1.0.0 -p minimal
Notes
- Produces apacheminificpp:minimal-1.0.0 (example)

6) Run the MiNiFi C++ Edge Agent
- ./DockerRun.sh --version 1.0.0 --prefix minimal --flow-config "/home/ubuntu/src/james/nifi-minifi-cpp/flows/bi_s2s_config.yml" -Z
What the script mounts
- Host root: /home/ubuntu/src/james/nifi-minifi-cpp/minifi-data -> /opt/minifi/minifi-current/data
- logs, flowfile_repository, content_repository, provenance_repository are mounted under /opt/minifi/minifi-current/...
MiNiFi flow essentials (bi_s2s_config.yml)
- GetFile reads: /opt/minifi/minifi-current/data/input/traffic_congest
- RPG to NiFi Input Port id: fbe5c098-019b-1000-f414-3bd10079fcd5 (RAW on nifi:10000)
- RPG from NiFi Output Port id: fbe5f8e5-019b-1000-0677-e8133da42b41
- Connection ToMiNiFiAgent1 -> PutFile uses relationship name: undefined (required by MiNiFi C++ to forward received FlowFiles)
- PutFile writes: /opt/minifi/minifi-current/data/output (Create Missing Directories: true; Conflict Resolution Strategy: replace)

7) Verify MiNiFi -> NiFi
- Place a file on the host at /home/ubuntu/src/james/nifi-minifi-cpp/minifi-data/input/traffic_congest/
- Observe in NiFi that FromMiNiFiAgent1 routes to LogAttribute and logs attributes
- MiNiFi logs should show successful S2S send to the NiFi input port

8) Verify NiFi -> MiNiFi
- The NiFi CreateFlowFile processor continuously sends a small message to ToMiNiFiAgent1
- MiNiFi receives and PutFile stores it at /home/ubuntu/src/james/nifi-minifi-cpp/minifi-data/output/
- MiNiFi logs show “Site to Site transaction ... received flow record 1, total length 37, added 37”

9) Secure configuration notes (optional)
- NiFi: run ./DockerRun.sh with AUTH=tls and provide keystore/truststore env vars; start.sh + secure.sh configure HTTPS and secure S2S
- NiFi Registry: run with AUTH=tls similarly (secure.sh requires keystore/truststore)
- MiNiFi: configure TLS client properties in minifi.properties (mount with --properties) to connect to NiFi secure S2S

10) Troubleshooting
- “destination port is in invalid state”
  - The NiFi RPG target port is disabled or the UUID is wrong; enable the port and ensure the MiNiFi YAML IDs match NiFi’s instanceIdentifier values.
- “no protocol, yielding”
  - RAW 10000/tcp is not reachable; verify NiFi container exposes 10000 and both containers share fleet-net; check start.sh applied nifi.remote.input.socket.port=10000.
- “File Operation: Failed to process flowfile content”
  - The PutFile Directory does not exist or is not writable; ensure /opt/minifi/minifi-current/data/output is within the mounted data root and Create Missing Directories: true is set.
  - Host volume permission issues: rerun MiNiFi with -Z (privileged) to test; confirm host paths are writable by Docker.
- Preflight checks
  - MiNiFi DockerRun.sh prints HTTP S2S API and RAW S2S status; use these to confirm NiFi is up and ports are reachable.
- Relationship on ToMiNiFiAgent1
  - Keep source relationship name: undefined for MiNiFi C++ to pass received FlowFiles to PutFile.

References
- NiFi flow: /home/ubuntu/src/james/nifi-minifi-cpp/docs/SiteToSite/nifi_flow/BiSiteToSiteNiFiAndMiNiFi.json
- MiNiFi YAML: /home/ubuntu/src/james/nifi-minifi-cpp/flows/bi_s2s_config.yml
- MiNiFi run: /home/ubuntu/src/james/nifi-minifi-cpp/docker/DockerRun.sh
- MiNiFi build: /home/ubuntu/src/james/nifi-minifi-cpp/docker/DockerBuild.sh
- NiFi run: /home/ubuntu/src/james/nifi/nifi-docker/dockerhub/DockerRun.sh
- NiFi build: /home/ubuntu/src/james/nifi/nifi-docker/dockerhub/DockerBuild.sh
- NiFi start scripts: /home/ubuntu/src/james/nifi/nifi-docker/dockerhub/sh/start.sh and secure.sh
- NiFi Registry run/build: /home/ubuntu/src/james/nifi/nifi-registry/nifi-registry-core/nifi-registry-docker/dockerhub/DockerRun.sh and DockerBuild.sh; start.sh and secure.sh
