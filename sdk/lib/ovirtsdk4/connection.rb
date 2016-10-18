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

require 'json'
require 'uri'

module OvirtSDK4

  #
  # This class is responsible for managing an HTTP connection to the engine server. It is intended as the entry
  # point for the SDK, and it provides access to the `system` service and, from there, to the rest of the services
  # provided by the API.
  #
  class Connection
    #
    # Creates a new connection to the API server.
    #
    # [source,ruby]
    # ----
    # connection = OvirtSDK4::Connection.new(
    #   :url      => 'https://engine.example.com/ovirt-engine/api',
    #   :username => 'admin@internal',
    #   :password => '...',
    #   :ca_file  => '/etc/pki/ovirt-engine/ca.pem',
    # )
    # ----
    #
    # @param opts [Hash] The options used to create the connection.
    #
    # @option opts [String] :url A string containing the base URL of the server, usually something like
    #   `\https://server.example.com/ovirt-engine/api`.
    #
    # @option opts [String] :username The name of the user, something like `admin@internal`.
    #
    # @option opts [String] :password The password of the user.
    #
    # @option opts [String] :token The token used to authenticate. Optionally the caller can explicitly provide
    #   the token, instead of the user name and password. If the token isn't provided then it will be automatically
    #   created.
    #
    # @option opts [Boolean] :insecure (false) A boolean flag that indicates if the server TLS certificate and host
    #   name should be checked.
    #
    # @option opts [String] :ca_file The name of a PEM file containing the trusted CA certificates. The certificate
    #   presented by the server will be verified using these CA certificates. If not set then the system wide CA
    #   certificates store is used.
    #
    # @option opts [Boolean] :debug (false) A boolean flag indicating if debug output should be generated. If the
    #   values is `true` and the `log` parameter isn't `nil` then the data sent to and received from the server will be
    #   written to the log. Be aware that user names and passwords will also be written, so handle with care.
    #
    # @option opts [Logger] :log The logger where the log messages will be written.
    #
    # @option opts [Boolean] :kerberos (false) A boolean flag indicating if Kerberos authentication should be used
    #   instead of user name and password to obtain the OAuth token.
    #
    # @option opts [Integer] :timeout (0) The maximun total time to wait for the response, in seconds. A value of zero
    #   (the default) means wait for ever. If the timeout expires before the response is received an exception will be
    #   raised.
    #
    # @option opts [Boolean] :compress (false) A boolean flag indicating if the SDK should ask the server to send
    #   compressed responses. Note that this is a hint for the server, and that it may return uncompressed data even
    #   when this parameter is set to `true`.
    #
    def initialize(opts = {})
      # Get the values of the parameters and assign default values:
      @url = opts[:url]
      @username = opts[:username]
      @password = opts[:password]
      @token = opts[:token]
      @insecure = opts[:insecure] || false
      @ca_file = opts[:ca_file]
      @debug = opts[:debug] || false
      @log = opts[:log]
      @kerberos = opts[:kerberos] || false
      @timeout = opts[:timeout] || 0
      @compress = opts[:compress] || false

      # Create the HTTP client:
      @client = HttpClient.new(
        :insecure => @insecure,
        :ca_file => @ca_file,
        :debug => @debug,
        :log => @log,
        :timeout => @timeout,
        :compress => @compress,
      )
    end

    #
    # Returns a reference to the root of the services tree.
    #
    # @return [SystemService]
    #
    def system_service
      @system_service ||= SystemService.new(self, "")
    end

    #
    # Returns a reference to the service corresponding to the given path. For example, if the `path` parameter
    # is `vms/123/diskattachments` then it will return a reference to the service that manages the disk
    # attachments for the virtual machine with identifier `123`.
    #
    # @param path [String] The path of the service, for example `vms/123/diskattachments`.
    # @return [Service]
    # @raise [Error] If there is no service corresponding to the given path.
    #
    def service(path)
      return system_service.service(path)
    end

    #
    # Sends an HTTP request and waits for the response.
    #
    # @param request [HttpRequest] The request object containing the details of the HTTP request to send.
    # @return [Response] A request object containing the details of the HTTP response received.
    #
    # @api private
    #
    def send(request)
      # Add the base URL to the request:
      if request.url.nil?
        request.url = @url
      else
        request.url = "#{@url}#{request.url}"
      end

      # Set the headers:
      request.headers.merge!(
        'User-Agent'   => "RubySDK/#{VERSION}",
        'Version'      => '4',
        'Content-Type' => 'application/xml',
        'Accept'       => 'application/xml',
      )

      # Set the authentication token:
      @token ||= get_access_token
      request.token = @token

      # Create an empty response:
      response = HttpResponse.new

      # Send the request and wait for the response:
      @client.send(request, response)

      # Return the response:
      return response
    end

    #
    # Obtains the access token from SSO to be used for bearer authentication.
    #
    # @return [String] The access token.
    #
    # @api private
    #
    def get_access_token
      # Build the URL and parameters required for the request:
      url, parameters = build_sso_auth_request

      # Send the response and wait for the request:
      response = get_sso_response(url, parameters)

      if response.is_a?(Array)
        response = response[0]
      end

      unless response['error'].nil?
        raise Error.new("Error during SSO authentication: #{response['error_code']}: #{response['error']}")
      end

      response['access_token']
    end

    #
    # Revoke the SSO access token.
    #
    # @api private
    #
    def revoke_access_token
      # Build the URL and parameters required for the request:
      url, parameters = build_sso_revoke_request

      response = get_sso_response(url, parameters)

      if response.is_a?(Array)
        response = response[0]
      end

      unless response['error'].nil?
        raise Error.new("Error during SSO revoke: #{response['error_code']}: #{response['error']}")
      end
    end

    #
    # Execute a get request to the SSO server and return the response.
    #
    # @param url [String] The URL of the SSO server.
    #
    # @param parameters [Hash] The parameters to send to the SSO server.
    #
    # @return [Hash] The JSON response.
    #
    # @api private
    #
    def get_sso_response(url, parameters)
      # Create the request:
      request = HttpRequest.new(
        :method => :POST,
        :url => url,
        :headers => {
          'User-Agent' => "RubySDK/#{VERSION}",
          'Content-Type' => 'application/x-www-form-urlencoded',
          'Accept' => 'application/json',
        },
        :body => URI.encode_www_form(parameters),
      )

      # Create an empty response:
      response = HttpResponse.new

      # Send the request and wait for the response:
      @client.send(request, response)

      # Parse and return the JSON response:
      JSON.parse(response.body)
    end

    #
    # Builds a the URL and parameters to acquire the access token from SSO.
    #
    # @return [Array] An array containing two elements, the first is the URL of the SSO service and the second is a hash
    #   containing the parameters required to perform authentication.
    #
    # @api private
    #
    def build_sso_auth_request
      # Compute the entry point and the parameters:
      parameters = {
        :scope => 'ovirt-app-api',
      }
      if @kerberos
        entry_point = 'token-http-auth'
        parameters.merge!(
          :grant_type => 'urn:ovirt:params:oauth:grant-type:http',
        )
      else
        entry_point = 'token'
        parameters.merge!(
          :grant_type => 'password',
          :username => @username,
          :password => @password,
        )
      end

      # Compute the URL:
      url = URI(@url.to_s)
      url.path = "/ovirt-engine/sso/oauth/#{entry_point}"
      url = url.to_s

      # Return the pair containing the URL and the parameters:
      [url, parameters]
    end

    #
    # Builds a the URL and parameters to revoke the SSO access token
    #
    # @return [Array] An array containing two elements, the first is the URL of the SSO service and the second is a hash
    #   containing the parameters required to perform the revoke.
    #
    # @api private
    #
    def build_sso_revoke_request
      # Compute the parameters:
      parameters = {
        :scope => '',
        :token => @token,
      }

      # Compute the URL:
      url = URI(@url.to_s)
      url.path = '/ovirt-engine/services/sso-logout'
      url = url.to_s

      # Return the pair containing the URL and the parameters:
      [url, parameters]
    end

    #
    # Tests the connectivity with the server. If connectivity works correctly it returns `true`. If there is any
    # connectivity problem it will either return `false` or raise an exception if the `raise_exception` parameter is
    # `true`.
    #
    # @param raise_exception [Boolean]
    # @return [Boolean]
    #
    def test(raise_exception = false)
      begin
        system_service.get
        true
      rescue Exception
        raise if raise_exception
        false
      end
    end

    #
    # Performs the authentication process and returns the authentication token. Usually there is no need to
    # call this method, as authentication is performed automatically when needed. But in some situations it
    # may be useful to perform authentication explicitly, and then use the obtained token to create other
    # connections, using the `token` parameter of the constructor instead of the user name and password.
    #
    # @return [String]
    #
    def authenticate
      @token ||= get_access_token
    end

    #
    # Indicates if the given object is a link. An object is a link if it has an `href` attribute.
    #
    # @return [Boolean]
    #
    def is_link?(object)
      !object.href.nil?
    end

    #
    # Follows the `href` attribute of the given object, retrieves the target object and returns it.
    #
    # @param object [Type] The object containing the `href` attribute.
    # @raise [Error] If the `href` attribute has no value, or the link can't be followed.
    #
    def follow_link(object)
      # Check that the "href" has a value, as it is needed in order to retrieve the representation of the object:
      href = object.href
      if href.nil?
        raise Error.new("Can't follow link because the 'href' attribute does't have a value")
      end

      # Check that the value of the "href" attribute is compatible with the base URL of the connection:
      prefix = URI(@url).path
      if !prefix.end_with?('/')
        prefix += '/'
      end
      if !href.start_with?(prefix)
        raise Error.new("The URL '#{href}' isn't compatible with the base URL of the connection")
      end

      # Remove the prefix from the URL, follow the path to the relevant service and invoke the "get" or "list" method
      # to retrieve its representation:
      path = href[prefix.length..-1]
      service = service(path)
      if object.is_a?(Array)
        service.list
      else
        service.get
      end
    end

    #
    # Releases the resources used by this connection.
    #
    def close
      # Revoke the SSO access token:
      revoke_access_token if @token

      # Close the HTTP client:
      @client.close if @client
    end

  end
end
