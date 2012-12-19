require 'net/http'
require 'open-uri'
require 'pathname'
require 'uri'
require 'puppet/forge/cache'
require 'puppet/forge/repository'
require 'puppet/forge/errors'

class Puppet::Forge
  # +consumer_name+ is a name to be used for identifying the consumer of the
  # forge and +consumer_semver+ is a SemVer object to identify the version of
  # the consumer
  def initialize(consumer_name, consumer_semver)
    @consumer_name = consumer_name
    @consumer_semver = consumer_semver
  end

  def remote_dependency_info(author, mod_name, version)
    version_string = version ? "&version=#{version}" : ''
    response = repository.make_http_request("/api/v1/releases.json?module=#{author}/#{mod_name}#{version_string}")
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
    version = "#{@consumer_name}/#{[@consumer_semver.major, @consumer_semver.minor, @consumer_semver.tiny].join('.')}#{@consumer_semver.special}"
    @repository ||= Puppet::Forge::Repository.new(Puppet[:module_repository], version)
  end
  private :repository
end
