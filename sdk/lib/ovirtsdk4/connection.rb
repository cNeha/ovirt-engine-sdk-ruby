#
# Copyright (c) 2015-2017 Red Hat, Inc.
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
require 'tempfile'
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
    #   url: 'https://engine.example.com/ovirt-engine/api',
    #   username: 'admin@internal',
    #   password: '...',
    #   ca_file:'/etc/pki/ovirt-engine/ca.pem'
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
    #   presented by the server will be verified using these CA certificates. If neither this nor the `ca_certs`
    #   options are provided, then the system wide CA certificates store is used. If both options are provided,
    #   then the certificates from both options will be trusted.
    #
    # @option opts [Array<String>] :ca_certs An array of strings containing the trusted CA certificates, in PEM
    #   format. The certificate presented by the server will be verified using these CA certificates. If neither this
    #   nor the `ca_file` options are provided, then the system wide CA certificates store is used. If both options
    #   are provided, then the certificates from both options will be trusted.
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
    # @option opts [Boolean] :compress (true) A boolean flag indicating if the SDK should ask the server to send
    #   compressed responses. Note that this is a hint for the server, and that it may return uncompressed data even
    #   when this parameter is set to `true`. Also, compression will be automatically disabled when the `debug`
    #   parameter is set to `true`, as otherwise the debug output will be compressed as well, and then it isn't
    #   useful.
    #
    # @option opts [String] :proxy_url A string containing the protocol, address and port number of the proxy server
    #   to use to connect to the server. For example, in order to use the HTTP proxy `proxy.example.com` that is
    #   listening on port `3128` the value should be `http://proxy.example.com:3128`. This is optional, and if not
    #   given the connection will go directly to the server specified in the `url` parameter.
    #
    # @option opts [String] :proxy_username The name of the user to authenticate to the proxy server.
    #
    # @option opts [String] :proxy_password The password of the user to authenticate to the proxy server.
    #
    # @option opts [Hash] :headers Custom HTTP headers to send with all requests. The keys of the hash can be
    #   strings of symbols, and they will be used as the names of the headers. The values of the hash will be used
    #   as the names of the headers. If the same header is provided here and in the `headers` parameter of a specific
    #   method call, then the `headers` parameter of the specific method call will have precedence.
    #
    # @option opts [Integer] :connections (0) The maximum number of connections to open to the host. If the value is
    #   `0` (the default) then the number of connections will be unlimited.
    #
    # @option opts [Integer] :pipeline (0) The maximum number of request to put in an HTTP pipeline without waiting for
    #   the response. If the value is `0` (the default) then pipelining is disabled.
    #
    def initialize(opts = {})
      # Get the values of the parameters and assign default values:
      @url = opts[:url]
      @username = opts[:username]
      @password = opts[:password]
      @token = opts[:token]
      @insecure = opts[:insecure] || false
      @ca_file = opts[:ca_file]
      @ca_certs = opts[:ca_certs]
      @debug = opts[:debug] || false
      @log = opts[:log]
      @kerberos = opts[:kerberos] || false
      @timeout = opts[:timeout] || 0
      @compress = opts[:compress] || true
      @proxy_url = opts[:proxy_url]
      @proxy_username = opts[:proxy_username]
      @proxy_password = opts[:proxy_password]
      @headers = opts[:headers]
      @connections = opts[:connections] || 0
      @pipeline = opts[:pipeline] || 0

      # Check that the URL has been provided:
      raise ArgumentError, "The 'url' option is mandatory" unless @url

      # Automatically disable compression when debug is enabled, as otherwise the debug output generated by
      # libcurl is also compressed, and that isn't useful for debugging:
      @compress = false if @debug

      # Create a temporary file to store the CA certificates, and populate it with the contents of the 'ca_file' and
      # 'ca_certs' options. The file will be removed when the connection is closed.
      @ca_store = nil
      if @ca_file || @ca_certs
        @ca_store = Tempfile.new('ca_store')
        @ca_store.write(::File.read(@ca_file)) if @ca_file
        if @ca_certs
          @ca_certs.each do |ca_cert|
            @ca_store.write(ca_cert)
          end
        end
        @ca_store.close
      end

      # Create the HTTP client:
      @client = HttpClient.new(
        insecure: @insecure,
        ca_file: @ca_store ? @ca_store.path : nil,
        debug: @debug,
        log: @log,
        timeout: @timeout,
        compress: @compress,
        proxy_url: @proxy_url,
        proxy_username: @proxy_username,
        proxy_password: @proxy_password,
        connections: @connections,
        pipeline: @pipeline
      )
    end

    #
    # Returns a reference to the root of the services tree.
    #
    # @return [SystemService]
    #
    def system_service
      @system_service ||= SystemService.new(self, '')
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
      system_service.service(path)
    end

    #
    # Sends an HTTP request.
    #
    # @param request [HttpRequest] The request object containing the details of the HTTP request to send.
    #
    # @api private
    #
    def send(request)
      # Add the base URL to the request:
      request.url = request.url.nil? ? request.url = @url : "#{@url}#{request.url}"

      # Set the headers common to all requests:
      request.headers.merge!(
        'User-Agent'   => "RubySDK/#{VERSION}",
        'Version'      => '4',
        'Content-Type' => 'application/xml',
        'Accept'       => 'application/xml'
      )

      # Older versions of the engine (before 4.1) required the 'all_content' as an HTTP header instead of a query
      # parameter. In order to better support those older versions of the engine we need to check if this parameter is
      # included in the request, and add the corresponding header.
      unless request.query.nil?
        all_content = request.query['all_content']
        request.headers['All-Content'] = all_content unless all_content.nil?
      end

      # Add the global headers, but without replacing the values that may already exist:
      request.headers.merge!(@headers) { |_name, local, _global| local } if @headers

      # Set the authentication token:
      @token ||= create_access_token
      request.token = @token

      # Send the request:
      @client.send(request)
    end

    #
    # Waits for the response to the given request.
    #
    # @param request [HttpRequest] The request object whose corresponding response you want to wait for.
    # @return [Response] A request object containing the details of the HTTP response received.
    #
    def wait(request)
      # Wait for the response:
      response = @client.wait(request)
      raise response if response.is_a?(Exception)

      # If the request failed because of authentication, and it wasn't a request to the SSO service, then the
      # most likely cause is an expired SSO token. In this case we need to request a new token, and try the original
      # request again, but only once. It if fails again, we just return the failed response.
      if response.code == 401 && request.token
        @token = create_access_token
        request.token = @token
        @client.send(request)
        response = @client.wait(request)
      end

      response
    end

    #
    # Obtains the access token from SSO to be used for bearer authentication.
    #
    # @return [String] The access token.
    #
    # @api private
    #
    def create_access_token
      # Build the URL and parameters required for the request:
      url, parameters = build_sso_auth_request

      # Send the request and wait for the request:
      response = get_sso_response(url, parameters)
      response = response[0] if response.is_a?(Array)

      # Check the response and raise an error if it contains an error code:
      code = response['error_code']
      error = response['error']
      raise Error, "Error during SSO authentication: #{code}: #{error}" if error

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

      # Send the request and wait for the response:
      response = get_sso_response(url, parameters)
      response = response[0] if response.is_a?(Array)

      # Check the response and raise an error if it contains an error code:
      code = response['error_code']
      error = response['error']
      raise Error, "Error during SSO revoke: #{code}: #{error}" if error
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
      request = HttpRequest.new
      request.method = :POST
      request.url = url
      request.headers = {
        'User-Agent' => "RubySDK/#{VERSION}",
        'Content-Type' => 'application/x-www-form-urlencoded',
        'Accept' => 'application/json'
      }
      request.body = URI.encode_www_form(parameters)

      # Add the global headers:
      request.headers.merge!(@headers) if @headers

      # Send the request and wait for the response:
      @client.send(request)
      response = @client.wait(request)
      raise response if response.is_a?(Exception)

      # Check the returned content type:
      check_json_content_type(response)

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
        scope: 'ovirt-app-api'
      }
      if @kerberos
        entry_point = 'token-http-auth'
        parameters[:grant_type] = 'urn:ovirt:params:oauth:grant-type:http'
      else
        entry_point = 'token'
        parameters.merge!(
          grant_type: 'password',
          username: @username,
          password: @password
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
        scope: '',
        token: @token
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
      system_service.get
      true
    rescue StandardError
      raise if raise_exception
      false
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
      @token ||= create_access_token
    end

    #
    # Indicates if the given object is a link. An object is a link if it has an `href` attribute.
    #
    # @return [Boolean]
    #
    def link?(object)
      !object.href.nil?
    end

    #
    # The `link?` method used to be named `is_link?`, and we need to preserve it for backwards compatibility, but try to
    # avoid using it.
    #
    # @return [Boolean]
    #
    # @deprecated Please use `link?` instead.
    #
    alias is_link? link?

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
        raise Error, "Can't follow link because the 'href' attribute doesn't have a value"
      end

      # Check that the value of the "href" attribute is compatible with the base URL of the connection:
      prefix = URI(@url).path
      prefix += '/' unless prefix.end_with?('/')
      unless href.start_with?(prefix)
        raise Error, "The URL '#{href}' isn't compatible with the base URL of the connection"
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

      # Remove the temporary file that contains the trusted CA certificates:
      @ca_store.unlink if @ca_store
    end

    #
    # Checks that the content type of the given response is JSON. If it is JSON then it does nothing. If it isn't
    # JSON then it raises an exception.
    #
    # @param response [HttpResponse] The HTTP response to check.
    #
    # @api private
    #
    def check_json_content_type(response)
      check_content_type(JSON_CONTENT_TYPE_RE, 'JSON', response)
    end

    #
    # Checks that the content type of the given response is XML. If it is XML then it does nothing. If it isn't
    # XML then it raises an exception.
    #
    # @param response [HttpResponse] The HTTP response to check.
    #
    # @api private
    #
    def check_xml_content_type(response)
      check_content_type(XML_CONTENT_TYPE_RE, 'XML', response)
    end

    #
    # Creates and raises an error containing the details of the given HTTP response.
    #
    # @param response [HttpResponse] The HTTP response where the details of the raised error will be taken from.
    # @param detail [String, Fault] (nil) The detail of the error. It can be a string or a `Fault` object.
    #
    # @api private
    #
    def raise_error(response, detail = nil)
      # Check if the detail is a fault:
      fault = detail.is_a?(Fault) ? detail : nil

      # Build the error message from the response and the fault:
      message = ''
      unless fault.nil?
        unless fault.reason.nil?
          message << ' ' unless message.empty?
          message << "Fault reason is \"#{fault.reason}\"."
        end
        unless fault.detail.nil?
          message << ' ' unless message.empty?
          message << "Fault detail is \"#{fault.detail}\"."
        end
      end
      unless response.nil?
        unless response.code.nil?
          message << ' ' unless message.empty?
          message << "HTTP response code is #{response.code}."
        end
        unless response.message.nil?
          message << ' ' unless message.empty?
          message << "HTTP response message is \"#{response.message}\"."
        end
      end

      # If the detail is a string, append it to the message:
      if detail.is_a?(String)
        message << ' ' unless message.empty?
        message << detail
        message << '.'
      end

      raise Error, message
    end

    private

    #
    # Regular expression used to check JSON content type.
    #
    # @api private
    #
    JSON_CONTENT_TYPE_RE = %r{^\s*(application|text)/json\s*(;.*)?$}i

    #
    # Regular expression used to check XML content type.
    #
    # @api private
    #
    XML_CONTENT_TYPE_RE = %r{^\s*(application|text)/xml\s*(;.*)?$}i

    #
    # The typical URL path, used just to generate informative error messages.
    #
    # @api private
    #
    TYPICAL_PATH = '/ovirt-engine/api'.freeze

    #
    # Checks the content type of the given HTTP response and raises an exception if it isn't the expected one.
    #
    # @param expected_re [Regex] The regular expression used to check the expected content type.
    # @param expected_name [String] The name of the expected content type.
    # @param response [HttpResponse] The HTTP response to check.
    #
    # @api private
    #
    def check_content_type(expected_re, expected_name, response)
      content_type = response.headers['content-type']
      return if expected_re =~ content_type
      detail = "The response content type '#{content_type}' isn't #{expected_name}"
      url = URI(@url)
      if url.path != TYPICAL_PATH
        detail << ". Is the path '#{url.path}' included in the 'url' parameter correct?"
        detail << " The typical one is '#{TYPICAL_PATH}'"
      end
      raise_error(response, detail)
    end
  end
end
