feat(minifi): stabilize bidirectional S2S with NiFi; fix edge file paths; add privileged toggle; improve preflight

Summary
- Enable reliable MiNiFi ↔ NiFi RAW S2S with correct port UUIDs and edge storage paths.
- Add optional --privileged and run options wiring; strengthen preflight checks.
- Align YAML flow relationships and directories with container mounts.

Changes
- docker/DockerRun.sh
  - Add -Z/--privileged flag; collect extra docker run opts via RUN_OPTS.
  - Standardize volume mounts to /opt/minifi/minifi-current/* for data, logs, repositories, conf.
  - Preflight: check NiFi HTTP S2S API and RAW 10000/tcp reachability; autodetect NiFi container and ports.
  - Print network/volume diagnostics; ensure shared network exists.
- examples/bi_s2s_config.yml (and flows/bi_s2s_config.yml)
  - Set PutFile Directory to /opt/minifi/minifi-current/data/output; Create Missing Directories: true; Conflict Resolution Strategy: replace.
  - Ensure ToMiNiFiAgent1 → PutFile uses source relationship name: undefined.
  - Reference NiFi port UUIDs: FromMiNiFiAgent1=fbe5c098-...; ToMiNiFiAgent1=fbe5f8e5-...
- cmake/MiNiFiOptions.cmake
  - Prepare options for Docker-driven paths and future flow/config injection (no runtime behavior change).

Rationale
- Prior PutFile failures traced to mismatched in-container paths/permissions; standardizing mounts fixes write operations.
- Privileged toggle helps diagnose host volume permission issues without forcing root-by-default.
- Explicit “undefined” relationship required for RemoteProcessorGroupPort → PutFile in MiNiFi C++ receive path.

Test Plan
- Build and run NiFi Registry and NiFi on fleet-net (HTTP: AUTH unset; HTTPS: AUTH=tls with keystore/truststore).
- Run MiNiFi:
  - ./docker/DockerRun.sh --version <ver> --prefix minimal --flow-config ./examples/bi_s2s_config.yml -Z
  - Verify preflight outputs: HTTP 200 at /nifi-api/site-to-site; RAW 10000 reachable.
- Verify flows:
  - MiNiFi → NiFi: drop file in minifi-data/input/traffic_congest; observe at NiFi via FromMiNiFiAgent1.
  - NiFi → MiNiFi: CreateFlowFile to ToMiNiFiAgent1; confirm PutFile writes to minifi-data/output and logs show 37 bytes received.

Notes
- Unsecured mode: start.sh forces nifi.remote.input.secure=false and clears TLS props to prevent keystore lookup.
- Secured mode: use secure.sh with KEYSTORE/TRUSTSTORE envs; configure MiNiFi TLS in minifi.properties when needed.
