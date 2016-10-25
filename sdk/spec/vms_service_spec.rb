#
# Copyright (c) 2015-2016 Red Hat, Inc.
#
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

describe SDK::VmsService do
  before(:all) do
    start_server
    @connection = test_connection
    @service = @connection.system_service.vms_service
  end

  after(:all) do
    @connection.close
    stop_server
  end

  describe '#add' do
    context 'when adding a VM with the `clone` parameter' do
      it 'send a POST request with a `clone` query parameter' do
        mount_xml(path: 'vms', status: 201, body: '<vm/>')
        vm = SDK::Vm.new
        @service.add(vm, clone: true)
        expect(last_request_query).to eql('clone=true')
      end
    end

    context 'when adding a VM with the `clone` and `clone_permissions` parameters' do
      it 'send a POST request with a `clone` and `clone_permissions` query parameters' do
        mount_xml(path: 'vms', status: 201, body: '<vm/>')
        vm = SDK::Vm.new
        @service.add(vm, clone: true, clone_permissions: true)
        expect(last_request_query).to eql('clone=true&clone_permissions=true')
      end
    end

    context 'when the server returns a 200 code' do
      it 'raises no exception' do
        mount_xml(path: 'vms', status: 200, body: '<vm/>')
        vm = SDK::Vm.new
        @service.add(vm)
      end
    end

    context 'when the server returns a 201 code' do
      it 'raises no exception' do
        mount_xml(path: 'vms', status: 201, body: '<vm/>')
        vm = SDK::Vm.new
        @service.add(vm)
      end
    end

    context 'when the server returns a 202 code' do
      it 'raises no exception' do
        mount_xml(path: 'vms', status: 202, body: '<vm/>')
        vm = SDK::Vm.new
        @service.add(vm)
      end
    end
  end

  describe '#nil?' do
    context 'getting the reference to the service' do
      it 'does not return nil' do
        expect(@service).not_to be_nil
      end
    end
  end

  describe '#list' do
    context 'without parameters' do
      it 'returns a list, maybe empty' do
        mount_xml(path: 'vms', body: '<vms/>')
        vms = @service.list
        expect(vms).not_to be_nil
        expect(vms).to be_an(Array)
      end
    end

    context 'with an unfeasible query' do
      it 'returns an empty array' do
        mount_xml(path: 'vms', body: '<vms/>')
        vms = @service.list(search: 'name=ugly')
        expect(vms).to eql([])
      end
    end
  end
end
