Bidirectional Site-to-Site (S2S) between NiFi and MiNiFi C++ — Role and Domain Guide

Purpose
- Provide role-based guidance for designing, deploying, and operating bidirectional S2S flows between NiFi (core/central) and MiNiFi C++ Edge Agents.
- Map features and patterns to Data Engineering, Software Engineering, Autonomous Systems, AI/ML, and critical domains.

Architecture overview
- NiFi (central): UI on 8080 (HTTP) or 8443 (HTTPS), RAW S2S on 10000/tcp, flow orchestration, provenance, registry integration.
- MiNiFi C++ (edge): lightweight runtime; YAML flow; Remote ports for sending to and receiving from NiFi; local repos for buffering.
- Bidirectional S2S: NiFi Input Port “FromMiNiFiAgent1” and Output Port “ToMiNiFiAgent1”; MiNiFi GetFile -> RPG to NiFi; NiFi CreateFlowFile -> RPG to MiNiFi -> PutFile.

References
- Setup guide: SiteToSiteGuide.md
- NiFi flow JSON: docs/SiteToSite/nifi_flow/BiSiteToSiteNiFiAndMiNiFi.json
- MiNiFi YAML: flows/bi_s2s_config.yml
- Docker scripts: nifi/nifi-docker/dockerhub/* and nifi-minifi-cpp/docker/*

Roles and responsibilities

Data Engineer perspective
- Ingestion and routing
  - Define Input/Output Ports in NiFi; configure RPGs in MiNiFi YAML for RAW S2S on nifi:10000.
  - Use GetFile on edge for directory ingestion; PutFile to persist incoming data from NiFi.
- Schema, lineage, governance
  - Enable NiFi Provenance and use LogAttribute/Record processors for auditing.
  - Integrate NiFi Registry for versioned flows and change tracking.
- Reliability
  - Configure backpressure on connections; use MiNiFi repositories for buffering when NiFi is unreachable.
  - Use Conflict Resolution Strategy in PutFile and Create Missing Directories for deterministic writes.
- Security and compliance
  - Unsecured: AUTH unset (HTTP + nifi.remote.input.secure=false).
  - Secured: AUTH=tls; set keystore/truststore in NiFi; configure MiNiFi TLS client in minifi.properties.

Software Engineer perspective
- Config as code
  - Keep bi_s2s_config.yml and BiSiteToSiteNiFiAndMiNiFi.json under version control; use NiFi Registry for flow lifecycle.
- CI/CD and containers
  - Build images via DockerBuild.sh; run via DockerRun.sh on a shared network (fleet-net).
  - Parameterize runtime via env (ports, AUTH) and mount-only conf files for immutability.
- Testability
  - Preflight checks: MiNiFi DockerRun.sh probes HTTP S2S (nifi-api/site-to-site) and RAW port reachability.
  - Use synthetic CreateFlowFile in NiFi to validate MiNiFi receive path and PutFile writes.
- Observability
  - Tail NiFi logs; MiNiFi logs indicate S2S transactions and failures (invalid port state, yielding, file ops).

Autonomous Systems Engineer perspective
- Edge constraints
  - MiNiFi C++ minimal footprint, C++ runtime, YAML flows; timer/event scheduling; RocksDB-backed state.
- Robust comms
  - RAW S2S for low overhead; connection backpressure; transaction-based send/receive.
  - Offline buffering with flowfile/content repositories; retries when NiFi ports recover.
- Deterministic operations
  - Use explicit directory paths mounted from host; ensure directory creation and replace strategy for repeatability.

AI/ML Engineer perspective
- Data pipelines
  - Edge feature extraction via MiNiFi processors; central orchestration in NiFi for labeling/ETL and model-serving triggers.
- Model lifecycle
  - Use NiFi Registry for flow versions; integrate model artifacts distribution through NiFi RPGs to MiNiFi.
- Monitoring and drift
  - Capture provenance; route telemetry back to NiFi; use reporting tasks to feed metrics sinks.

Critical domain patterns

Medical Robotics
- Requirements: strict audit, secure transport, deterministic edge writes.
- Pattern: MiNiFi PutFile in a write-only directory; NiFi secured S2S (AUTH=tls) with keystore/truststore; heavy provenance.

Self-Driving Cars
- Requirements: high-rate telemetry; intermittent connectivity.
- Pattern: MiNiFi buffers locally; RAW S2S transactions; NiFi central aggregation and replay; backpressure tuned.

Unmanned Aircraft Systems (UAS)
- Requirements: low-latency edge processing, store-and-forward.
- Pattern: Event-driven scheduling on MiNiFi; small message CreateFlowFile from NiFi for control signals; PutFile confirm logs.

Micro Factory Manufacturing (Robotic 3D Printing Cells)
- Requirements: reliable job dispatch and status returns.
- Pattern: NiFi -> MiNiFi (job commands); MiNiFi -> NiFi (status/artifacts); directories mapped to host storage; conflict strategy replace.

Humanoid Robotics
- Requirements: multimodal data, edge fusion, central coordination.
- Pattern: MiNiFi processes sensor batches; NiFi orchestration and enrichment; secure mode in shared environments.

Features applied (NiFi and MiNiFi C++)
- Site-to-Site (RAW/HTTP)
  - Input/Output Ports; Remote Processor Group Port; transactional send/receive; compression optional.
- Ports and RPGs
  - NiFi Input (FromMiNiFiAgent1), Output (ToMiNiFiAgent1); UUID mapping in MiNiFi YAML; RAW port 10000.
- Scheduling and flow control
  - TIMER_DRIVEN and EVENT_DRIVEN processors; yield/penalization periods; backpressure on connections.
- Repositories and state
  - MiNiFi FlowFile/Content/Provenance repositories; RocksDB state storage; NiFi repositories for durability.
- Provenance and logging
  - LogAttribute and NiFi provenance views; MiNiFi transaction logs showing bytes received/sent.
- Registry integration
  - NiFi Registry NAR provider; flow import/export; versioning and change control.
- Extensions
  - Python extensions directory and NAR autoload directory managed by NiFi start.sh; optional edge Python via NiFi (central).
- Security
  - Unsecured mode: HTTP + nifi.remote.input.secure=false; explicit cleanup of TLS props.
  - Secured mode: keystore/truststore configured via secure.sh; HTTPS UI; secure S2S; authorizers and identity providers.

Operational checklist (derived from SiteToSiteGuide.md)
- Shared Docker network fleet-net; run NiFi Registry (optional), NiFi, MiNiFi C++.
- Import NiFi flow JSON; enable FromMiNiFiAgent1 and ToMiNiFiAgent1; confirm UUIDs.
- In MiNiFi YAML, set:
  - GetFile input directory under /opt/minifi/minifi-current/data/input/...
  - RPG destination/source IDs to match NiFi’s instanceIdentifier.
  - ToMiNiFiAgent1 -> PutFile with source relationship name: undefined.
  - PutFile Directory under /opt/minifi/minifi-current/data/output; Create Missing Directories: true; Conflict Resolution Strategy: replace.
- Start MiNiFi with DockerRun.sh; use -Z (privileged) or --as-root when host volume permissions are restrictive.

Performance tuning
- Batch sizes and transaction frequency in S2S; enable compression for WAN links; adjust scheduling periods.
- Backpressure thresholds to prevent memory pressure; set repository paths to fast storage.

Security and compliance
- TLS everywhere in regulated domains; enforce managed-authorizer; initial admin identity/group in secure.sh.
- Maintain audit trails via NiFi provenance and deterministic edge storage with PutFile.

Troubleshooting
- “destination port is in invalid state”: NiFi port disabled or wrong UUID; enable port and correct MiNiFi YAML IDs.
- “no protocol, yielding”: RAW 10000 not reachable; check network and NiFi start.sh port config.
- “File Operation: Failed to process flowfile content”: directory missing or unwritable; fix PutFile Directory or host mount permissions; use -Z/--as-root to test.
