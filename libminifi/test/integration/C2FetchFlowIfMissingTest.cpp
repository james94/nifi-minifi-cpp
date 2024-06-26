/**
 *
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#include "integration/HTTPIntegrationBase.h"
#include "integration/HTTPHandlers.h"
#include "unit/TestUtils.h"
#include "utils/file/PathUtils.h"
#include "unit/Catch.h"

using namespace std::literals::chrono_literals;

namespace org::apache::nifi::minifi::test {

TEST_CASE("C2FetchFlowIfMissingTest", "[c2test]") {
  TestController controller;
  auto minifi_home = controller.createTempDirectory();
  const auto test_file_path = std::filesystem::path(TEST_RESOURCES) / "TestEmpty.yml";
  C2FlowProvider handler(test_file_path.string());
  VerifyFlowFetched harness(10s);
  harness.setKeyDir(TEST_RESOURCES);
  harness.setUrl("https://localhost:0/", &handler);
  harness.setFlowUrl(harness.getC2RestUrl());

  harness.run(minifi_home / "config.yml");

  // check existence of the config file
  REQUIRE(std::ifstream{minifi_home / "config.yml"});
}

}  // namespace org::apache::nifi::minifi::test
