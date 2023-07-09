#!/bin/bash
#
# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

source "$(dirname "$0")/../../lib/init.sh"
source module ci/lib/io.sh
source module ci/cloudbuild/builds/lib/vcpkg.sh
source module ci/cloudbuild/builds/lib/cmake.sh

io::log_h2 "Building with clang-tidy"
mapfile -t cmake_args < <(cmake::common_args)
mapfile -t vcpkg_args < <(vcpkg::cmake_args)
io::run cmake "${cmake_args[@]}" "${vcpkg_args[@]}" \
  -DFUNCTIONS_FRAMEWORK_CPP_ENABLE_WERROR=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_COMPILER=g++
io::run cmake --build cmake-out

mapfile -t ctest_args < <(ctest::common_args)
io::run ctest "${ctest_args[@]}"
