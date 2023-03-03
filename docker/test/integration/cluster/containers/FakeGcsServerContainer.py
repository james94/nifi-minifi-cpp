# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
import logging
import os
from .Container import Container


class FakeGcsServerContainer(Container):
    def __init__(self, name, vols, network, image_store, command=None):
        super().__init__(name, 'fake-gcs-server', vols, network, image_store, command)

    def get_startup_finished_log_entry(self):
        return "server started at http"

    def deploy(self):
        if not self.set_deployed():
            return

        logging.info('Creating and running google cloud storage server docker container...')
        self.client.containers.run(
            "fsouza/fake-gcs-server:latest",
            detach=True,
            name=self.name,
            network=self.network.name,
            entrypoint=self.command,
            ports={'4443/tcp': 4443},
            volumes=[os.environ['TEST_DIRECTORY'] + "/resources/fake-gcs-server-data:/data"],
            command='-scheme http -host fake-gcs-server')
        logging.info('Added container \'%s\'', self.name)