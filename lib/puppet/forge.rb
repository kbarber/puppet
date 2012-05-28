require 'net/http'
require 'open-uri'
require 'pathname'
require 'uri'
require 'puppet/forge/cache'
require 'puppet/forge/repository'

# This class represents the main user object for the Forge client API.
class Puppet::Forge

  # Create a new instance of the Forge client API
  #
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
  def initialize(opts={})
    @opts = opts
  end

  # Return a list of module metadata hashes that match the search query.
  # This return value is used by the module_tool face install search,
  # and displayed to on the console.
  #
  # Example return value:
  #
  # [
  #   {
  #     "author"      => "puppetlabs",
  #     "name"        => "bacula",
  #     "tag_list"    => ["backup", "bacula"],
  #     "releases"    => [{"version"=>"0.0.1"}, {"version"=>"0.0.2"}],
  #     "full_name"   => "puppetlabs/bacula",
  #     "version"     => "0.0.2",
  #     "project_url" => "http://github.com/puppetlabs/puppetlabs-bacula",
  #     "desc"        => "bacula"
  #   }
  # ]
  #
  def search(term)
    server = Puppet.settings[:module_repository].sub(/^(?!https?:\/\/)/, 'http://')
    Puppet.notice "Searching #{server} ..."
    response = repository.get("/modules.json?q=#{URI.escape(term)}")

    case response.code
    when "200"
      matches = PSON.parse(response.body)
    else
      raise RuntimeError, "Could not execute search (HTTP #{response.code})"
    end

    matches
  end

  def remote_dependency_info(author, mod_name, version)
    version_string = version ? "&version=#{version}" : ''
    response = repository.get("/api/v1/releases.json?module=#{author}/#{mod_name}#{version_string}")
    json = PSON.parse(response.body) rescue {}
    case response.code
    when "200"
      return json
    else
      error = json['error'] || ''
      if error =~ /^Module #{author}\/#{mod_name} has no release/
        return []
      else
        raise RuntimeError, "Could not find release information for this module (#{author}/#{mod_name}) (HTTP #{response.code})"
      end
    end
  end

  # @!group Token Related Instance Methods

  # Obtain the current user token for the authenticated forge account.
  def token
    response = repository.get("/api/v1/token.json")
    case response.code
    when "200"
      matches = PSON.parse(response.body)
    else
      begin
        error_hash = PSON.parse(response.body)
        error = error_hash['error'] || 'Unknown'
      rescue PSON::ParseError
        error = response.body
      ensure
        raise RuntimeError, "HTTP Error: #{error} (Status #{response.code})"
      end
    end
  end

  # @!group Module Related Instance Methods

  # Publish a module to the forge using a module package file
  #
  # @param file [File] the file reference to publish
  def module_publish(file)
    original = file.read

    base64 = Base64.encode64(original)
    payload = {
      'module' => base64,
    }

    response = repository.submit_command("publish module", 1, payload.to_pson)
  end

  # @!endgroup

  def get_release_packages_from_repository(install_list)
    install_list.map do |release|
      modname, version, file = release
      cache_path = nil
      if file
        begin
          cache_path = repository.retrieve(file)
        rescue OpenURI::HTTPError => e
          raise RuntimeError, "Could not download module: #{e.message}"
        end
      else
        raise RuntimeError, "Malformed response from module repository."
      end
      cache_path
    end
  end

  # Locate a module release package on the local filesystem and move it
  # into the `Puppet.settings[:module_working_dir]`. Do not unpack it, just
  # return the location of the package on disk.
  def get_release_package_from_filesystem(filename)
    if File.exist?(File.expand_path(filename))
      repository = Repository.new('file:///')
      uri = URI.parse("file://#{URI.escape(File.expand_path(filename))}")
      cache_path = repository.retrieve(uri)
    else
      raise ArgumentError, "File does not exists: #{filename}"
    end

    cache_path
  end

  def retrieve(release)
    repository.retrieve(release)
  end

  def uri
    repository.uri
  end

  def repository
    @repository ||= Puppet::Forge::Repository.new(Puppet[:module_repository], @opts)
  end
  private :repository
end
