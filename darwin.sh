#!/bin/bash
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

verify_enable_platform() {
    feature="$1"
    if [ "$feature" = "BUSTACHE_ENABLED" ]; then
        BUSTACHE_MAX="9"
        ## we should check the xcode version
        CLANG_VERSION=$(clang --version | head -n 1 | awk '{print $4}')
        CLANG_MAJOR=$(echo "$CLANG_VERSION" | cut -d. -f1)
        if [ "$CLANG_MAJOR" -ge "$BUSTACHE_MAX" ]; then
            echo "false"
        else
            echo "true"
        fi
    else
        echo "true"
    fi
}

add_os_flags(){
    :
}

install_bison() {
    BISON_INSTALLED="false"
    if [ -x "$(command -v bison)" ]; then
        BISON_VERSION=$(bison --version | head -n 1 | awk '{print $4}')
        BISON_MAJOR=$(echo "$BISON_VERSION" | cut -d. -f1)
        if (( BISON_MAJOR >= 3 )); then
            BISON_INSTALLED="true"
        fi
    fi
    if [ "$BISON_INSTALLED" = "false" ]; then
        wget https://ftp.gnu.org/gnu/bison/bison-3.0.5.tar.xz
        tar xvf bison-3.0.5.tar.xz
        pushd bison-3.0.5 || exit 1
        ./configure
        make
        sudo make install
        popd || exit 2
    fi

}

bootstrap_cmake(){
    brew install cmake
}
bootstrap_compiler() {
    :
}
build_deps(){

    COMMAND="brew install cmake perl bzip2"
    INSTALLED=()
    for option in "${OPTIONS[@]}" ; do
        option_value="${!option}"
        if [ "$option_value" = "${TRUE}" ]; then
            # option is enabled
            FOUND_VALUE=""
            for cmake_opt in "${DEPENDENCIES[@]}" ; do
                KEY=${cmake_opt%%:*}
                VALUE=${cmake_opt#*:}
                if [ "$KEY" = "$option" ]; then
                    FOUND_VALUE="$VALUE"
                    if [ "$FOUND_VALUE" = "bison" ]; then
                        install_bison
                    elif [ "$FOUND_VALUE" = "flex" ]; then
                        INSTALLED+=("flex")
                    elif [ "$FOUND_VALUE" = "python" ]; then
                        INSTALLED+=("python")
                    elif [ "$FOUND_VALUE" = "libtool" ]; then
                        INSTALLED+=("libtool")
                    elif [ "$FOUND_VALUE" = "automake" ]; then
                        INSTALLED+=("automake")
                        INSTALLED+=("autoconf")
                    elif [ "$FOUND_VALUE" = "libarchive" ]; then
                        INSTALLED+=("bzip2")
                    elif [ "$FOUND_VALUE" = "libssh2" ]; then
                        INSTALLED+=("libssh2")
                    fi
                fi
            done

        fi
    done

    for option in "${INSTALLED[@]}" ; do
        COMMAND="${COMMAND} $option"
    done

    echo "Ensuring you have all dependencies installed..."
    ${COMMAND} > /dev/null 2>&1
}
