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

describe SDK::Connection do
  before(:all) do
    start_server
    mount_xml(path: '', body: '<api/>')
  end

  after(:all) do
    stop_server
  end

  describe '.new' do
    context 'in secure mode' do
      it 'no exception is raised if no CA certificate is provided' do
        connection = SDK::Connection.new(
          url:      test_url,
          username: test_user,
          password: test_password,
          debug:    test_debug,
          log:      test_log
        )
        connection.close
      end

      it 'no exception is raised if a CA certificate is provided' do
        connection = SDK::Connection.new(
          url:      test_url,
          username: test_user,
          password: test_password,
          ca_file:  test_ca_file,
          debug:    test_debug,
          log:      test_log
        )
        connection.close
      end
    end

    context 'in insecure mode' do
      it 'a CA certificate is not required' do
        connection = SDK::Connection.new(
          url:      test_url,
          username: test_user,
          password: test_password,
          insecure: true,
          debug:    test_debug,
          log:      test_log
        )
        connection.close
      end
    end

    context 'with Kerberos enabled' do
      it 'works correctly' do
        connection = SDK::Connection.new(
          url:      test_url,
          kerberos: true,
          ca_file:  test_ca_file,
          debug:    test_debug,
          log:      test_log
        )
        connection.close
      end
    end

    context 'with version suffix' do
      it 'works correctly' do
        connection = SDK::Connection.new(
          url:     "#{test_url}/v4",
          ca_file: test_ca_file,
          debug:   test_debug,
          log:     test_log
        )
        connection.close
      end
    end

    context 'with token and no user or password' do
      it 'works correctly' do
        connection = SDK::Connection.new(
          url:     test_url,
          token:   test_token,
          ca_file: test_ca_file,
          debug:   test_debug,
          log:     test_log
        )
        connection.close
      end
    end

    it 'raises exception if no URL is provided' do
      options = {
        token:   test_token,
        ca_file: test_ca_file,
        debug:   test_debug,
        log:     test_log
      }
      expect { SDK::Connection.new(options) }.to raise_error(ArgumentError, /url/)
    end

    it 'raises exception if the maximum number of connections is zero' do
      options = {
        url:         test_url,
        token:       test_token,
        ca_file:     test_ca_file,
        debug:       test_debug,
        log:         test_log,
        connections: 0
      }
      expect { SDK::Connection.new(options) }.to raise_error(ArgumentError, /minimum is 1/)
    end

    it 'raises exception if the maximum number of connections is negative' do
      options = {
        url:         test_url,
        token:       test_token,
        ca_file:     test_ca_file,
        debug:       test_debug,
        log:         test_log,
        connections: -1
      }
      expect { SDK::Connection.new(options) }.to raise_error(ArgumentError, /minimum is 1/)
    end

    it 'raises exception if the maximum pipeline length is negative' do
      options = {
        url:      test_url,
        token:    test_token,
        ca_file:  test_ca_file,
        debug:    test_debug,
        log:      test_log,
        pipeline: -1
      }
      expect { SDK::Connection.new(options) }.to raise_error(ArgumentError, /minimum is 0/)
    end

    it 'raises exception if the maximum number of connections is negative' do
      options = {
        url:         test_url,
        token:       test_token,
        ca_file:     test_ca_file,
        debug:       test_debug,
        log:         test_log,
        connections: -1
      }
      expect { SDK::Connection.new(options) }.to raise_error(ArgumentError, /minimum is 1/)
    end
  end

  describe '#authenticate' do
    context 'with user name and password' do
      it 'returns the expected token' do
        connection = SDK::Connection.new(
          url:      test_url,
          username: test_user,
          password: test_password,
          ca_file:  test_ca_file,
          debug:    test_debug,
          log:      test_log
        )
        token = connection.authenticate
        expect(token).to eql(test_token)
        connection.close
      end
    end

    context 'with Kerberos' do
      it 'returns the expected token' do
        connection = SDK::Connection.new(
          url:      test_url,
          kerberos: true,
          ca_file:  test_ca_file,
          debug:    test_debug,
          log:      test_log
        )
        token = connection.authenticate
        expect(token).to eql(test_token)
        connection.close
      end
    end

    context 'with token' do
      it 'returns the expected token' do
        connection = SDK::Connection.new(
          url:     test_url,
          token:   test_token,
          ca_file: test_ca_file,
          debug:   test_debug,
          log:     test_log
        )
        token = connection.authenticate
        expect(token).to eql(test_token)
        connection.close
      end
    end

    context 'with CA certificate as string' do
      it 'returns the expected token' do
        ca_cert = File.read(test_ca_file)
        connection = SDK::Connection.new(
          url:      test_url,
          token:    test_token,
          ca_certs: [ca_cert],
          debug:    test_debug,
          log:      test_log
        )
        token = connection.authenticate
        expect(token).to eql(test_token)
        connection.close
      end
    end

    context 'with multiple CA certificates as strings' do
      it 'returns the expected token' do
        ca_cert = File.read(test_ca_file)
        connection = SDK::Connection.new(
          url:      test_url,
          token:    test_token,
          ca_certs: [ca_cert, ca_cert],
          debug:    test_debug,
          log:      test_log
        )
        token = connection.authenticate
        expect(token).to eql(test_token)
        connection.close
      end
    end

    context 'with CA certificate as file and string' do
      it 'returns the expected token' do
        ca_cert = File.read(test_ca_file)
        connection = SDK::Connection.new(
          url:      test_url,
          token:    test_token,
          ca_file:  test_ca_file,
          ca_certs: [ca_cert],
          debug:    test_debug,
          log:      test_log
        )
        token = connection.authenticate
        expect(token).to eql(test_token)
        connection.close
      end
    end

    context 'without CA certificates in insecure mode' do
      it 'returns the expected token' do
        connection = SDK::Connection.new(
          url:      test_url,
          token:    test_token,
          debug:    test_debug,
          log:      test_log,
          insecure: true
        )
        token = connection.authenticate
        expect(token).to eql(test_token)
        connection.close
      end
    end
  end
end
