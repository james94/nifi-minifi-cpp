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
#include "utils/gsl.h"
#include "unit/TestUtils.h"

using namespace std::literals::chrono_literals;

namespace org::apache::nifi::minifi::test {

TEST_CASE("Test update configuration C2 command", "[c2test]") {
  const auto test_file_path = std::filesystem::path(TEST_RESOURCES) / "TestHTTPGet.yml";
  C2UpdateHandler handler(test_file_path.string());
  VerifyC2Update harness(10s);
  harness.setKeyDir(TEST_RESOURCES);
  harness.setUrl("https://localhost:0/update", &handler);
  handler.setC2RestResponse(harness.getC2RestUrl(), "configuration");

  const auto start = std::chrono::steady_clock::now();

  harness.run(test_file_path);

  const auto then = std::chrono::steady_clock::now();
  const auto seconds = std::chrono::duration_cast<std::chrono::seconds>(then - start).count();
  REQUIRE(handler.getCallCount() <= gsl::narrow<size_t>(seconds + 1));
}

}  // namespace org::apache::nifi::minifi::test
