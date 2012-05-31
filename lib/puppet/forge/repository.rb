require 'net/http'
require 'digest/sha1'
require 'uri'

class Puppet::Forge
  # = Repository
  #
  # This class is a file for accessing remote repositories with modules.
  class Repository
    attr_reader :uri, :cache

    # Instantiate a new repository instance rooted at the +url+.
    #
    # @param [String, URI] uri URI of the Forge.
    def initialize(uri, opts)
      @opts = opts
      @uri = uri.is_a?(::URI) ? uri : ::URI.parse(uri.sub(/^(?!https?:\/\/)/, 'http://'))
      @cache = Cache.new(self)
    end

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

    # Return a Net::HTTPResponse read for this +request_path+.
    def get(request_path, params={})
      request = Net::HTTP::Get.new(request_path, { "User-Agent" => user_agent })
      if ! @opts[:username].nil? && ! @opts[:password].nil?
        request.basic_auth(@opts[:username], @opts[:password])
      elsif ! @opts[:auth_token].nil?
        request['X-AUTH-TOKEN'] = @opts[:auth_token]
      end
      return read_response(request)
    end

    # Return a Net::HTTPResponse from a post to the +request_path+.
    def post(request_path, params={})
      request = Net::HTTP::Post.new(request_path, { "User-Agent" => user_agent })
      request.set_form_data(params)
      if ! @opts[:username].nil? && ! @opts[:password].nil?
        request.basic_auth(@opts[:username], @opts[:password])
      elsif ! @opts[:auth_token].nil?
        request['X-AUTH-TOKEN'] = @opts[:auth_token]
      end
      return read_response(request)
    end

    # Specific helper for submitting commands to the commands API on the forge
    #
    # @param command [String] command to send to the forge.
    # @param version [Fixnum] version of the command.
    # @param payload [String] string of payload. For complex structures it is
    #   recommended to use JSON, or for binary data you can use base64.
    # @return [Net::HTTPResponse] object representation of the http response.
    def submit_command(command, version, payload)
      path = "/api/v1/commands"

      command = {
        :command => command,
        :version => version,
        :payload => payload,
      }
      command_json = command.to_pson

      params = {
        'payload'  => command_json,
        'checksum' => Digest::SHA1.hexdigest(command_json),
      }

      post(path, params)
    end

    # Return a Net::HTTPResponse read from this HTTPRequest +request+.
    def read_response(request)
      begin
        Net::HTTP::Proxy(
            http_proxy_host,
            http_proxy_port
            ).start(@uri.host, @uri.port) do |http|
          http.request(request)
        end
      rescue Errno::ECONNREFUSED, SocketError
        msg = "Error: Could not connect to #{@uri}\n"
        msg << "  There was a network communications problem\n"
        msg << "    Check your network connection and try again\n"
        Puppet.err msg
        exit(1)
      end
    end

    # Return the local file name containing the data downloaded from the
    # repository at +release+ (e.g. "myuser-mymodule").
    def retrieve(release)
      return cache.retrieve(@uri + release)
    end

    # Return the URI string for this repository.
    def to_s
      return @uri.to_s
    end

    # Return the cache key for this repository, this a hashed string based on
    # the URI.
    def cache_key
      return @cache_key ||= [
        @uri.to_s.gsub(/[^[:alnum:]]+/, '_').sub(/_$/, ''),
        Digest::SHA1.hexdigest(@uri.to_s)
      ].join('-')
    end

    def user_agent
      "#{consumer_version} Puppet/#{Puppet.version} (#{Facter.value(:operatingsystem)} #{Facter.value(:operatingsystemrelease)}) #{ruby_version}"
    end
    private :user_agent

    def consumer_version
      "#{@opts[:consumer_name]}/#{[@opts[:consumer_semver].major, @opts[:consumer_semver].minor, @opts[:consumer_semver].tiny].join('.')}#{@opts[:consumer_semver].special}"
    end

    def ruby_version
      # the patchlevel is not available in ruby 1.8.5
      patch = defined?(RUBY_PATCHLEVEL) ? "-p#{RUBY_PATCHLEVEL}" : ""
      "Ruby/#{RUBY_VERSION}#{patch} (#{RUBY_RELEASE_DATE}; #{RUBY_PLATFORM})"
    end
    private :ruby_version
  end
end
