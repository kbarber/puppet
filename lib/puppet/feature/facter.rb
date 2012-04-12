require 'puppet/util/feature'
require 'semver'

# See if Facter is available, and check revision
Puppet.features.add(:facter) do
  required_facter = "2.0.0"

  begin
    require 'facter'
  rescue LoadError
    require 'rubygems'
    require 'facter'
  end

  if ! defined?(::Facter)
    Puppet::Error "Cannot find Facter class. Facter may not be installed, " +
      "or not be in your RUBYLIB."
    false
  elsif ! defined?(::Facter.version)
    Puppet::Error "Cannot find Facter version declaration. Your " +
      "installation of Facter may be invalid, very old or this may be a bug."
  else
    facter_version = ::SemVer.new(::Facter.version)
    required_version = ::SemVer.new(required_facter)
    if facter_version >= required_version
      true
    else
      raise Puppet::Error, "Found Facter version #{::Facter.version} " +
        "however version #{required_facter} (or greater) is required for " +
        "Puppet to operate"
    end
  end
end

