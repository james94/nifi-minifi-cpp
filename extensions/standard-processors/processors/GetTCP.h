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
#ifndef EXTENSIONS_STANDARD_PROCESSORS_PROCESSORS_GETTCP_H_
#define EXTENSIONS_STANDARD_PROCESSORS_PROCESSORS_GETTCP_H_

#include <map>
#include <memory>
#include <string>
#include <vector>
#include <atomic>

#include "../core/state/nodes/MetricsBase.h"
#include "FlowFileRecord.h"
#include "core/Processor.h"
#include "core/ProcessSession.h"
#include "core/Core.h"
#include "core/Resource.h"
#include "concurrentqueue.h"
#include "utils/ThreadPool.h"
#include "core/logging/LoggerConfiguration.h"
#include "controllers/SSLContextService.h"

namespace org {
namespace apache {
namespace nifi {
namespace minifi {
namespace processors {

class SocketAfterExecute : public utils::AfterExecute<int> {
 public:
  explicit SocketAfterExecute(std::atomic<bool> &running, const std::string &endpoint, std::map<std::string, std::future<int>*> *list, std::mutex *mutex)
      : running_(running.load()),
        endpoint_(endpoint),
        mutex_(mutex),
        list_(list) {
  }

  explicit SocketAfterExecute(SocketAfterExecute && other) {
  }

  ~SocketAfterExecute() = default;

  virtual bool isFinished(const int &result) {
    if (result == -1 || result == 0 || !running_) {
      std::lock_guard<std::mutex> lock(*mutex_);
      list_->erase(endpoint_);
      return true;
    } else {
      return false;
    }
  }
  virtual bool isCancelled(const int &result) {
    if (!running_)
      return true;
    else
      return false;
  }

  virtual std::chrono::milliseconds wait_time() {
    // wait 500ms
    return std::chrono::milliseconds(500);
  }

 protected:
  std::atomic<bool> running_;
  std::string endpoint_;
  std::mutex *mutex_;
  std::map<std::string, std::future<int>*> *list_;
};

class DataHandlerCallback : public OutputStreamCallback {
 public:
  DataHandlerCallback(uint8_t *message, size_t size)
      : message_(message),
        size_(size) {
  }

  virtual ~DataHandlerCallback() = default;

  virtual int64_t process(const std::shared_ptr<io::BaseStream>& stream) {
    return stream->write(message_, size_);
  }

 private:
  uint8_t *message_;
  size_t size_;
};

class DataHandler {
 public:
  DataHandler(std::shared_ptr<core::ProcessSessionFactory> sessionFactory) // NOLINT
      : sessionFactory_(sessionFactory) {
  }
  static const char *SOURCE_ENDPOINT_ATTRIBUTE;

  int16_t handle(std::string source, uint8_t *message, size_t size, bool partial);

 private:
  std::shared_ptr<core::ProcessSessionFactory> sessionFactory_;
};

class GetTCPMetrics : public state::response::ResponseNode {
 public:
  GetTCPMetrics()
      : state::response::ResponseNode("GetTCPMetrics") {
    iterations_ = 0;
    accepted_files_ = 0;
    input_bytes_ = 0;
  }

  GetTCPMetrics(std::string name, utils::Identifier &uuid)
      : state::response::ResponseNode(name, uuid) {
    iterations_ = 0;
    accepted_files_ = 0;
    input_bytes_ = 0;
  }
  virtual ~GetTCPMetrics() = default;
  virtual std::string getName() const {
    return core::Connectable::getName();
  }

  virtual std::vector<state::response::SerializedResponseNode> serialize() {
    std::vector<state::response::SerializedResponseNode> resp;

    state::response::SerializedResponseNode iter;
    iter.name = "OnTriggerInvocations";
    iter.value = (uint32_t)iterations_.load();

    resp.push_back(iter);

    state::response::SerializedResponseNode accepted_files;
    accepted_files.name = "AcceptedFiles";
    accepted_files.value = (uint32_t)accepted_files_.load();

    resp.push_back(accepted_files);

    state::response::SerializedResponseNode input_bytes;
    input_bytes.name = "InputBytes";
    input_bytes.value = (uint32_t)input_bytes_.load();

    resp.push_back(input_bytes);

    return resp;
  }

 protected:
  friend class GetTCP;

  std::atomic<size_t> iterations_;
  std::atomic<size_t> accepted_files_;
  std::atomic<size_t> input_bytes_;
};

// GetTCP Class
class GetTCP : public core::Processor, public state::response::MetricsNodeSource {
 public:
// Constructor
  /*!
   * Create a new processor
   */
  explicit GetTCP(std::string name, utils::Identifier uuid = utils::Identifier())
      : Processor(name, uuid),
        running_(false),
        stay_connected_(true),
        concurrent_handlers_(2),
        endOfMessageByte(13),
        reconnect_interval_(5000),
        receive_buffer_size_(16 * 1024 * 1024),
        connection_attempt_limit_(3),
        ssl_service_(nullptr),
        logger_(logging::LoggerFactory<GetTCP>::getLogger()) {
    metrics_ = std::make_shared<GetTCPMetrics>();
  }
// Destructor
  virtual ~GetTCP() = default;
// Processor Name
  static constexpr char const* ProcessorName = "GetTCP";

  // Supported Properties
  static core::Property EndpointList;
  static core::Property ConcurrentHandlers;
  static core::Property ReconnectInterval;
  static core::Property StayConnected;
  static core::Property ReceiveBufferSize;
  static core::Property SSLContextService;
  static core::Property ConnectionAttemptLimit;
  static core::Property EndOfMessageByte;

  // Supported Relationships
  static core::Relationship Success;
  static core::Relationship Partial;

 public:
  /**
   * Function that's executed when the processor is scheduled.
   * @param context process context.
   * @param sessionFactory process session factory that is used when creating
   * ProcessSession objects.
   */
  virtual void onSchedule(const std::shared_ptr<core::ProcessContext> &processContext, const std::shared_ptr<core::ProcessSessionFactory> &sessionFactory);

  void onSchedule(core::ProcessContext *processContext, core::ProcessSessionFactory *sessionFactory) {
    throw std::exception();
  }
  /**
   * Execution trigger for the GetTCP Processor
   * @param context processor context
   * @param session processor session reference.
   */
  virtual void onTrigger(const std::shared_ptr<core::ProcessContext> &context, const std::shared_ptr<core::ProcessSession> &session);

  virtual void onTrigger(core::ProcessContext *context, core::ProcessSession *session) {
    throw std::exception();
  }

  // Initialize, over write by NiFi GetTCP
  virtual void initialize(void);

  int16_t getMetricNodes(std::vector<std::shared_ptr<state::response::ResponseNode>> &metric_vector);

 protected:
  virtual void notifyStop();

 private:
  std::function<int()> f_ex;

  std::atomic<bool> running_;

  std::unique_ptr<DataHandler> handler_;

  std::vector<std::string> endpoints;

  std::map<std::string, std::future<int>*> live_clients_;

  utils::ThreadPool<int> client_thread_pool_;

  moodycamel::ConcurrentQueue<std::unique_ptr<io::Socket>> socket_ring_buffer_;

  bool stay_connected_;

  uint16_t concurrent_handlers_;

  int8_t endOfMessageByte;

  uint64_t reconnect_interval_;

  uint64_t receive_buffer_size_;

  uint16_t connection_attempt_limit_;

  std::shared_ptr<GetTCPMetrics> metrics_;

  // Mutex for ensuring clients are running

  std::mutex mutex_;

  std::shared_ptr<minifi::controllers::SSLContextService> ssl_service_;

  // last listing time for root directory ( if recursive, we will consider the root
  // as the top level time.

  std::shared_ptr<logging::Logger> logger_;
};

REGISTER_RESOURCE(GetTCP, "Establishes a TCP Server that defines and retrieves one or more byte messages from clients");


}  // namespace processors
}  // namespace minifi
}  // namespace nifi
}  // namespace apache
}  // namespace org

#endif  // EXTENSIONS_STANDARD_PROCESSORS_PROCESSORS_GETTCP_H_
