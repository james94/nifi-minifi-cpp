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

#include "RocksDatabase.h"
#include "core/logging/LoggerConfiguration.h"
#include "utils/StringUtils.h"
#include "RocksDbInstance.h"

namespace org {
namespace apache {
namespace nifi {
namespace minifi {
namespace internal {

std::shared_ptr<core::logging::Logger> RocksDatabase::logger_ = core::logging::LoggerFactory<RocksDatabase>::getLogger();

std::unique_ptr<RocksDatabase> RocksDatabase::create(const DBOptionsPatch& db_options_patch, const ColumnFamilyOptionsPatch& cf_options_patch, const std::string& uri, RocksDbMode mode) {
  const std::string scheme = "minifidb://";

  logger_->log_info("Acquiring database handle '%s'", uri);
  std::string db_path = uri;
  std::string db_column = "default";
  if (utils::StringUtils::startsWith(uri, scheme)) {
    const std::string path = uri.substr(scheme.length());
    logger_->log_info("RocksDB scheme is detected in '%s'", uri);
    // last segment is treated as the column name
    std::string::size_type pos = path.find_last_of('/');
    if (pos == std::string::npos) {
      pos = path.find_last_of('\\');
    }
    if (pos == std::string::npos) {
      logger_->log_error("Couldn't detect the column name in '%s'", uri);
      return nullptr;
    }
    db_path = path.substr(0, pos);
    db_column = path.substr(pos + 1);
    logger_->log_info("Using column '%s' in rocksdb database '%s'", db_column, db_path);
  } else {
    logger_->log_info("Simple directory detected '%s', using as is", uri);
  }

  if (mode == RocksDbMode::ReadOnly) {
    // no need to cache anything with read-only databases
    return utils::make_unique<RocksDatabase>(std::make_shared<RocksDbInstance>(db_path, mode), db_column, db_options_patch, cf_options_patch);
  }

  static std::mutex mtx;
  static std::unordered_map<std::string, std::weak_ptr<RocksDbInstance>> databases;

  std::shared_ptr<RocksDbInstance> instance;
  {
    std::lock_guard<std::mutex> guard(mtx);
    instance = databases[db_path].lock();
    if (!instance) {
      logger_->log_info("Opening rocksdb database '%s'", db_path);
      instance = std::make_shared<RocksDbInstance>(db_path, mode);
      databases[db_path] = instance;
    } else {
      logger_->log_info("Using previously opened rocksdb instance '%s'", db_path);
    }
  }
  return utils::make_unique<RocksDatabase>(instance, db_column, db_options_patch, cf_options_patch);
}

RocksDatabase::RocksDatabase(std::shared_ptr<RocksDbInstance> db, std::string column, DBOptionsPatch db_options_patch, ColumnFamilyOptionsPatch cf_options_patch)
  : db_(std::move(db)), column_(std::move(column)), db_options_patch_(std::move(db_options_patch)), cf_options_patch_(std::move(cf_options_patch)) {}

utils::optional<OpenRocksDb> RocksDatabase::open() {
  return db_->open(column_, db_options_patch_, cf_options_patch_);
}

}  // namespace internal
}  // namespace minifi
}  // namespace nifi
}  // namespace apache
}  // namespace org