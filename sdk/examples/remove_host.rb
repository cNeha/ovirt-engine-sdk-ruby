#!/usr/bin/ruby

#
# Copyright (c) 2016 Red Hat, Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'ovirt/sdk/v4'

# This example will connect to the server, search for a host by name and
# remove it:

# Create the connection to the server:
connection = Ovirt::SDK::V4::Connection.new({
  :url => 'https://engine40.example.com/ovirt-engine/api',
  :username => 'admin@internal',
  :password => 'redhat123',
  :ca_file => 'ca.pem',
  :debug => true,
})

# Find the service that manages hosts:
hosts_service = connection.system_service.hosts_service

# Find the host:
host = hosts_service.list({:search => 'name=myhost'})[0]

# Find the service that manages the host:
host_service = hosts_service.host_service(host.id)

# If the host isn't down or in maintenance then move it to maintenance:
unless host.status.state == Ovirt::SDK::V4::HostStatus::MAINTENANCE
  host_service.deactivate
end

# Remove the host:
host_service.remove

# Close the connection to the server:
connection.close
