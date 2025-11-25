# MiNiFi C++ — Project structure and top-level build flow

This document explains how the top-level CMakeLists.txt orchestrates the MiNiFi C++ build, the order of subprojects, and the main folders in the tree.

## 1) High-level build flow (top-level CMakeLists.txt)
1. Basic initialization
   - cmake_minimum_required, project() and default CMAKE_BUILD_TYPE.
   - Option/variable initialization (BUILD_NUMBER, DOCKER_*, BUILD_IDENTIFIER).
2. Early exits
   - If DOCKER_BUILD_ONLY is set in DockerConfig, top-level returns early.
3. Global compiler / platform setup
   - Compiler flags for MSVC/GNU/Clang.
   - Position independent code (CMAKE_POSITION_INDEPENDENT_CODE ON).
   - ASAN / coverage / LTO conditional flags.
   - Threads discovery (find_package(Threads REQUIRED)).
4. Third-party and bundled libs
   - Uses many custom cmake modules (cmake/*) to locate or build bundled components:
     - OpenSSL, zlib, cURL, spdlog, yaml-cpp, libsodium, RapidJSON, concurrentqueue, gsl-lite, date, magic_enum, etc.
   - Some thirdparty directories are added via add_subdirectory (e.g., Simple-Windows-Posix-Semaphore on Windows).
5. Helper functions defined
   - append_third_party_passthrough_args, add_minifi_library, add_minifi_executable — used by subprojects to get consistent compile options and definitions.
6. Extensions discovery
   - PugiXML include and then iterate over extensions/* directories; if they contain CMakeLists.txt they are added.
7. Core subprojects added (order matters)
   - add_subdirectory(minifi-api)
   - add_subdirectory(core-framework)
   - add_subdirectory(extension-framework)
   - add_subdirectory(libminifi)
   - add_subdirectory(minifi_main)
   - Conditional: add_subdirectory(encrypt-config) if ENABLE_ENCRYPT_CONFIG
   - Conditional: add_subdirectory(controller) if ENABLE_CONTROLLER
8. Packaging and installer generation
   - CPACK settings and platform-specific packaging (TGZ, RPM, WIX on Windows).
   - Files and directories installed depend on MINIFI_PACKAGING_TYPE (RPM or TGZ).
9. Tests
   - If NOT SKIP_TESTS, enable_testing() and add many test directories:
     - libminifi/test/libtest, unit, integration, keyvalue-tests, flow-tests, schema-tests, optional persistence-tests, plus minifi_main/tests, encrypt-config/tests, controller/tests, etc.
10. Utility targets
    - linter, shellcheck, flake8, coverage target (conditional on MINIFI_ADVANCED_CODE_COVERAGE).

## 2) Subproject build order and purpose
Listed in the order they are added in the top-level CMakeLists.txt:

- minifi-api
  - Public API interfaces and shared headers used by other components.
- core-framework
  - Core runtime components and utilities used by processors and libs.
- extension-framework
  - Framework for building extensions and integrating processors.
- libminifi
  - Main implementation library that compiles the core agent implementation.
- minifi_main
  - The executable targets and main application wiring (depends on libminifi).
- encrypt-config (optional)
  - Tools for encrypting configuration if ENABLE_ENCRYPT_CONFIG is set.
- controller (optional)
  - Controller components for centralized management if ENABLE_CONTROLLER is set.
- packaging (added near the end)
  - Build/packaging scripts and CPACK integration for creating TGZ/RPM/WIX outputs.

Extensions:
- The CMakeLists enumerates extensions in extensions/* and adds each that contains CMakeLists.txt.
- Some extensions are conditionally included (e.g., civetweb and related features are added if ENABLE_ALL or specific flags are set).

## 3) Important global variables and flags that influence build
- DOCKER_BUILD_ONLY — if true, top-level returns early (docker-only workflow).
- BUILD_IDENTIFIER — generated randomly if not provided.
- MINIFI_PACKAGING_TYPE — must be RPM or TGZ for non-Windows packaging flows.
- SKIP_TESTS — if not set, tests are enabled and many test directories are added.
- ENABLE_* flags — many flags control optional features (ENABLE_ROCKSDB, ENABLE_LIBARCHIVE, ENABLE_BZIP2, ENABLE_PROMETHEUS, ENABLE_GRAFANA_LOKI, ENABLE_CIVET, ENABLE_ENCRYPT_CONFIG, ENABLE_CONTROLLER, etc).
- CUSTOM_MALLOC — jemalloc/mimalloc/rpmalloc integration logic.
- MINIFI_ADVANCED_ASAN_BUILD, MINIFI_ADVANCED_CODE_COVERAGE, MINIFI_ADVANCED_LINK_TIME_OPTIMIZATION — advanced build modes.
- MINIFI_FAIL_ON_WARNINGS — toggles -Werror or /WX.

## 4) Top-level directory map (key folders)
- cmake/                 — custom CMake modules used to find/build third parties.
- thirdparty/            — bundled external libraries not built via system packages (some may be added via add_subdirectory).
- extensions/            — extension modules; each extension subdirectory that has a CMakeLists.txt is added.
- minifi-api/            — public API headers and small sources.
- core-framework/        — core runtime sources and utilities.
- extension-framework/   — extension loading and framework code.
- libminifi/             — main agent implementation compiled into libminifi.
- minifi_main/           — executables and applications (add_subdirectory near the end).
- conf/                  — configuration files installed for packaging.
- bin/                   — scripts and runtime binaries to install.
- packaging/             — packaging metadata and platform-specific packaging helpers.
- docs/                  — documentation (this file lives here).
- libminifi/test/        — unit/integration tests and test utilities.
- packaging/msi/         — Windows installer resources (WIX templates).
- fips/                  — files used for FIPS/OpenSSL packaging.

## 5) Tests and CI-related targets
- If tests are enabled, the top-level file adds many test subdirectories:
  - libtest, unit, integration, keyvalue-tests, flow-tests, schema-tests, persistence-tests (conditional), minifi_main/tests, encrypt-config/tests, controller/tests.
- Utility targets:
  - linter — runs google-styleguide linter
  - shellcheck, flake8 — only on non-Windows hosts
  - coverage — when MINIFI_ADVANCED_CODE_COVERAGE is set

## 6) Packaging notes
- CPACK is configured for RPM (with many RPM specific variables) or TGZ; Windows creates WIX-based installers.
- Packaging installs:
  - LICENSE, NOTICE, docs, and config files.
  - For RPM: FHS layout (sysconf, /var/lib, /var/log) and user/group settings.
  - For TGZ: produces a self-contained archive.

## 7) Quick build commands
- Basic debug build:
  - mkdir build && cd build
  - cmake -G Ninja -DCMAKE_BUILD_TYPE=Debug ..
  - ninja
- Build with tests:
  - cmake -S . -B build -DSKIP_TESTS=OFF
  - cmake --build build --target all
  - ctest --test-dir build
- Create packaging (example TGZ):
  - cmake -S . -B build -DMINIFI_PACKAGING_TYPE=TGZ
  - cmake --build build --target package

## 8) How subprojects typically use the top-level helpers
- add_minifi_library(name TYPE sources...)
  - Ensures consistent compile options and definitions are applied.
- add_minifi_executable(name sources...)
  - Same for executables.
- append_third_party_passthrough_args()
  - Used when launching ExternalProjectAdd for third-party builds with consistent CMAKE args.

## 9) Tips for navigation
- To see the exact order of compilation and dependencies, inspect the targets created in the build tree (cmake --build . --verbose) or open generated build files (Ninja/Makefiles).
- For extension selection and CPACK components, inspect how selected_extensions is defined (property EXTENSION-OPTIONS) and the CPACK component generation block.

(End of document)
