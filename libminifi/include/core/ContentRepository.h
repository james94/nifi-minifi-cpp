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
#ifndef LIBMINIFI_INCLUDE_CORE_CONTENTREPOSITORY_H_
#define LIBMINIFI_INCLUDE_CORE_CONTENTREPOSITORY_H_

#include <map>
#include <memory>
#include <string>

#include "properties/Configure.h"
#include "ResourceClaim.h"
#include "io/BufferStream.h"
#include "io/BaseStream.h"
#include "StreamManager.h"
#include "core/Connectable.h"
#include "ContentSession.h"
#include "utils/GeneralUtils.h"

namespace org {
namespace apache {
namespace nifi {
namespace minifi {
namespace core {

/**
 * Content repository definition that extends StreamManager.
 */
class ContentRepository : public StreamManager<minifi::ResourceClaim>, public utils::EnableSharedFromThis<ContentRepository> {
 public:
  virtual ~ContentRepository() = default;

  /**
   * initialize this content repository using the provided configuration.
   */
  virtual bool initialize(const std::shared_ptr<Configure> &configure) = 0;

  virtual std::string getStoragePath() const;

  virtual std::shared_ptr<ContentSession> createSession();

  /**
   * Stops this repository.
   */
  virtual void stop() = 0;

  void reset();

  virtual uint32_t getStreamCount(const minifi::ResourceClaim &streamId);

  virtual void incrementStreamCount(const minifi::ResourceClaim &streamId);

  virtual StreamState decrementStreamCount(const minifi::ResourceClaim &streamId);

 protected:
  std::string directory_;

  std::mutex count_map_mutex_;

  std::map<std::string, uint32_t> count_map_;
};

}  // namespace core
}  // namespace minifi
}  // namespace nifi
}  // namespace apache
}  // namespace org

#endif  // LIBMINIFI_INCLUDE_CORE_CONTENTREPOSITORY_H_
