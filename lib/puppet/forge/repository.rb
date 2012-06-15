require 'net/https'
require 'digest/sha1'
require 'uri'
require 'puppet/forge/errors'

class Puppet::Forge
  # = Repository
  #
  # This class is a file for accessing remote repositories with modules.
  class Repository
    include Puppet::Forge::Errors

    attr_reader :uri, :cache

    # Instantiate a new repository instance rooted at the +url+.
    #
    # @param [String, URI] uri URI of the Forge.
    # @option opts [String] :username Username to use for HTTP basic
    #   authentication
    # @option opts [String] :password Password to use for HTTP basic
    #   authentication
    # @option opts [String] :auth_token Authentication token to use when
    #   interacting with the Forge.
    # @option opts [String] :consumer_name A name to be used for identifying the
    #   consumer of the Forge.
    # @option opts [SemVer] :consumer_semver Is a SemVer object to identify the
    #   version of the consumer
    def initialize(uri, opts)
      @opts = opts
      @uri = url.is_a?(::URI) ? url : ::URI.parse(url)
      @cache = Cache.new(self)
    end

    # @!group HTTP Proxy Instance Methods

    # Read HTTP proxy configurationm from Puppet's config file, or the
    # http_proxy environment variable.
    def http_proxy_env
      proxy_env = ENV["http_proxy"] || ENV["HTTP_PROXY"] || nil
      begin
        return URI.parse(proxy_env) if proxy_env
      rescue URI::InvalidURIError
        return nil
      end
      return nil
    end

    def http_proxy_host
      env = http_proxy_env

      if env and env.host then
        return env.host
      end

      if Puppet.settings[:http_proxy_host] == 'none'
        return nil
      end

      return Puppet.settings[:http_proxy_host]
    end

    def http_proxy_port
      env = http_proxy_env

      if env and env.port then
        return env.port
      end

      return Puppet.settings[:http_proxy_port]
    end

    # @!group HTTP Request Instance Methods

    # Perform a GET request to the forge.
    #
    # @todo Convert params for 'gets' into QSA automatically. Currently they
    #   they need to be encoded first, and passed in the path param.
    # @param request_path [String] relative request URL on the forge
    # @param params [Hash{String => String}]
    # @return [Net::HTTPResponse] object representing the response
    def get(request_path, params={})
      request(:get, request_path, params)
    end

    # Perform a POST request to the forge.
    #
    # @param request_path [String] relative request URL on the forge
    # @param params [Hash{String => String}]
    # @return [Net::HTTPResponse] object representing the response
    def post(request_path, params={})
      request(:post, request_path, params)
    end

    # Perform a HEAD request to the forge.
    #
    # @param request_path [String] relative request URL on the forge
    # @param params [Hash{String => String}]
    # @return [Net::HTTPResponse] object representing the response
    def head(request_path, params={})
      request(:head, request_path, params)
    end

    # Perform a PUT request to the forge.
    #
    # @param request_path [String] relative request URL on the forge
    # @param params [Hash{String => String}]
    # @return [Net::HTTPResponse] object representing the response
    def put(request_path, params={})
      request(:put, request_path, params)
    end

    # Perform a DELETE request to the forge.
    #
    # @param request_path [String] relative request URL on the forge
    # @param params [Hash{String => String}]
    # @return [Net::HTTPResponse] object representing the response
    def delete(request_path, params={})
      request(:delete, request_path, params)
    end

    # Perform a OPTIONS request to the forge.
    #
    # @param request_path [String] relative request URL on the forge
    # @param params [Hash{String => String}]
    # @return [Net::HTTPResponse] object representing the response
    def options(request_path, params={})
      request(:options, request_path, params)
    end

    # Generic low-level handler for preparing and making requests to the forge.
    # This is not normally called by itself, instead you should use the
    # http method specific ruby methods that are already provided in this
    # class.
    #
    # @todo Convert params for 'gets' into QSA automatically. Currently they
    #   they need to be encoded first, and passed in the path param.
    # @see #get
    # @see #post
    # @see #head
    # @see #put
    # @see #delete
    # @see #options
    # @param method [Symbol] the method to use in the request (see RFC2616
    #   Section 9). Currently supports: :get, :post, :head, :put, :delete &
    #   :options.
    # @param path [String] the relative path to request from the repository
    # @param params [Hash{String => String}] a hash of parameters to pass
    #   either in the body or in the querys string of the request.
    # @return [Net::HTTPResponse] object representing the response
    def request(method, path, params={})
      initheader = { "User-Agent" => user_agent }
      case method
      when :get
        request = Net::HTTP::Get.new(path, initheader)
      when :post
        request = Net::HTTP::Post.new(path, initheader)
        request.content_type = 'application/json'
        request.body = params.to_pson
      when :head
        request = Net::HTTP::Head.new(path, initheader)
      when :put
        request = Net::HTTP::Put.new(path, initheader)
      when :delete
        request = Net::HTTP::Delete.new(path, initheader)
      when :options
        request = Net::HTTPGenericRequest.new('OPTIONS', true, true, path, initheader)
      else
        raise ArgumentError, "Unsupported HTTP method #{verb}"
      end

      if ! @opts[:username].nil? && ! @opts[:password].nil?
        request.basic_auth(@opts[:username], @opts[:password])
      elsif ! @opts[:auth_token].nil?
        request['X-Auth-Token'] = @opts[:auth_token]
      end

      begin
        proxy_class = Net::HTTP::Proxy(http_proxy_host, http_proxy_port)
        proxy = proxy_class.new(@uri.host, @uri.port)

        if @uri.scheme == 'https'
          cert_store = OpenSSL::X509::Store.new
          cert_store.set_default_paths

          proxy.use_ssl = true
          proxy.verify_mode = OpenSSL::SSL::VERIFY_PEER
          proxy.cert_store = cert_store
        end

        proxy.start do |http|
          http.request(request)
        end
      rescue Errno::ECONNREFUSED, SocketError
        raise CommunicationError.new(:uri => @uri.to_s)
      rescue OpenSSL::SSL::SSLError => e
        if e.message =~ /certificate verify failed/
          raise SSLVerifyError.new(:uri => @uri.to_s)
        else
          raise e
        end
      end
    end

    # @!group Cache Related Instance Methods

    # Return the local file name containing the data downloaded from the
    # repository at +release+ (e.g. "myuser-mymodule").
    def retrieve(release)
      return cache.retrieve(@uri + release)
    end

    # Return the cache key for this repository, this a hashed string based on
    # the URI.
    def cache_key
      return @cache_key ||= [
        @uri.to_s.gsub(/[^[:alnum:]]+/, '_').sub(/_$/, ''),
        Digest::SHA1.hexdigest(@uri.to_s)
      ].join('-')
    end

    # @!group Other Informational Instance Methods

    # Return the URI string for this repository.
    #
    # @return [String] the URI
    def to_s
      return @uri.to_s
    end

    # Return the UserAgent header we use for requests.
    #
    # @return [String] the UserAgent header value
    def user_agent
      "#{consumer_version} Puppet/#{Puppet.version} (#{Facter.value(:operatingsystem)} #{Facter.value(:operatingsystemrelease)}) #{ruby_version}"
    end

    private

    def consumer_version
      "#{@opts[:consumer_name]}/#{[@opts[:consumer_semver].major, @opts[:consumer_semver].minor, @opts[:consumer_semver].tiny].join('.')}#{@opts[:consumer_semver].special}"
    end

    def ruby_version
      # the patchlevel is not available in ruby 1.8.5
      patch = defined?(RUBY_PATCHLEVEL) ? "-p#{RUBY_PATCHLEVEL}" : ""
      "Ruby/#{RUBY_VERSION}#{patch} (#{RUBY_RELEASE_DATE}; #{RUBY_PLATFORM})"
    end
  end
end
