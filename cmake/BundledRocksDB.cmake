# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

function(use_bundled_rocksdb SOURCE_DIR BINARY_DIR)
    message("Using bundled RocksDB")

    if(USE_CONAN_PACKAGER)
        message("Using Conan Packager to manage installing prebuilt RocksDB external lib")
        include(${CMAKE_BINARY_DIR}/RocksDBConfig.cmake)

    elseif(USE_CMAKE_FETCH_CONTENT)
        message("Using CMAKE's FetchContent to manage source building RocksDB external lib")


        if (NOT WIN32)
            include(Zstd)
            list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake/zstd/dummy")

            include(LZ4)
            list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake/lz4/dummy")
        endif()

        # Patch to fix build issue on ARM7 architecture: https://github.com/facebook/rocksdb/issues/8609#issuecomment-1009572506
        set(PATCH_FILE_1 "${SOURCE_DIR}/thirdparty/rocksdb/all/patches/arm7.patch")
        set(PATCH_FILE_2 "${SOURCE_DIR}/thirdparty/rocksdb/all/patches/dboptions_equality_operator.patch")
        set(PC ${Bash_EXECUTABLE} -c "set -x &&\
                (\"${Patch_EXECUTABLE}\" -p1 -R -s -f --dry-run -i \"${PATCH_FILE_1}\" || \"${Patch_EXECUTABLE}\" -p1 -N -i \"${PATCH_FILE_1}\") &&\
                (\"${Patch_EXECUTABLE}\" -p1 -R -s -f --dry-run -i \"${PATCH_FILE_2}\" || \"${Patch_EXECUTABLE}\" -p1 -N -i \"${PATCH_FILE_2}\") ")

        # Define byproducts
        if (WIN32)
            set(BYPRODUCT "lib/rocksdb.lib")
        else()
            include(GNUInstallDirs)
            string(REPLACE "/" ";" LIBDIR_LIST ${CMAKE_INSTALL_LIBDIR})
            list(GET LIBDIR_LIST 0 LIBDIR)
            set(BYPRODUCT "${LIBDIR}/librocksdb.a")
        endif()

        # Set build options
        set(ROCKSDB_CMAKE_ARGS ${PASSTHROUGH_CMAKE_ARGS}
                "-DCMAKE_INSTALL_PREFIX=${BINARY_DIR}/thirdparty/rocksdb-install"
                -DWITH_TESTS=OFF
                -DWITH_TOOLS=ON
                -DWITH_GFLAGS=OFF
                -DUSE_RTTI=1
                -DROCKSDB_BUILD_SHARED=OFF
                -DFAIL_ON_WARNINGS=OFF
                )
        if(PORTABLE)
            list(APPEND ROCKSDB_CMAKE_ARGS -DPORTABLE=ON)
        endif()
        if(WIN32)
            list(APPEND ROCKSDB_CMAKE_ARGS
                    -DROCKSDB_INSTALL_ON_WINDOWS=ON
                    -DWITH_XPRESS=ON)
        else()
            list(APPEND ROCKSDB_CMAKE_ARGS
                    -DWITH_ZLIB=ON
                    -DWITH_BZ2=ON
                    -DWITH_ZSTD=ON
                    -DWITH_LZ4=ON)
        endif()

        append_third_party_passthrough_args(ROCKSDB_CMAKE_ARGS "${ROCKSDB_CMAKE_ARGS}")

        # Build project
        ExternalProject_Add(
                rocksdb-external
                URL "https://github.com/facebook/rocksdb/archive/refs/tags/v8.10.2.tar.gz"
                URL_HASH "SHA256=44b6ec2f4723a0d495762da245d4a59d38704e0d9d3d31c45af4014bee853256"
                SOURCE_DIR "${BINARY_DIR}/thirdparty/rocksdb-src"
                CMAKE_ARGS ${ROCKSDB_CMAKE_ARGS}
                PATCH_COMMAND ${PC}
                BUILD_BYPRODUCTS "${BINARY_DIR}/thirdparty/rocksdb-install/${BYPRODUCT}"
                EXCLUDE_FROM_ALL TRUE
                LIST_SEPARATOR % # This is needed for passing semicolon-separated lists
        )

        # Set variables
        set(ROCKSDB_FOUND "YES" CACHE STRING "" FORCE)
        set(ROCKSDB_INCLUDE_DIR "${BINARY_DIR}/thirdparty/rocksdb-install/include" CACHE STRING "" FORCE)
        set(ROCKSDB_LIBRARY "${BINARY_DIR}/thirdparty/rocksdb-install/${BYPRODUCT}" CACHE STRING "" FORCE)
        set(ROCKSDB_LIBRARIES ${ROCKSDB_LIBRARY} CACHE STRING "" FORCE)

        # Create imported targets
        add_library(RocksDB::rocksdb STATIC IMPORTED)
        set_target_properties(RocksDB::rocksdb PROPERTIES IMPORTED_LOCATION "${ROCKSDB_LIBRARY}")
        if (NOT WIN32)
            add_dependencies(rocksdb-external ZLIB::ZLIB BZip2::BZip2 zstd::zstd lz4::lz4)
        endif()
        add_dependencies(RocksDB::rocksdb rocksdb-external)
        file(MAKE_DIRECTORY ${ROCKSDB_INCLUDE_DIR})
        target_include_directories(RocksDB::rocksdb INTERFACE ${ROCKSDB_INCLUDE_DIR})
        set_property(TARGET RocksDB::rocksdb APPEND PROPERTY INTERFACE_LINK_LIBRARIES Threads::Threads)
        target_link_libraries(RocksDB::rocksdb INTERFACE Threads::Threads)
        if(WIN32)
            target_link_libraries(RocksDB::rocksdb INTERFACE Rpcrt4.lib Cabinet.lib)
        else()
            target_link_libraries(RocksDB::rocksdb INTERFACE ZLIB::ZLIB BZip2::BZip2 zstd::zstd lz4::lz4)
        endif()
    endif()

endfunction(use_bundled_rocksdb)
