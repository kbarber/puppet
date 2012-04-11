require 'puppet/util/feature'
require 'semver'

# See if Facter is available, and check revision
Puppet.features.add(:facter) do
  begin
    require 'facter'
  rescue LoadError => detail
    require 'rubygems'
    require 'facter'
  end

  if ! (defined?(::Facter) and defined?(::Facter.version))
    Puppet.err "Cannot find Facter class or version declaration"
    false
  else
    facter_version = ::SemVer.new(::Facter.version)
    required_version = ::SemVer.new("2.0.0")
    if facter_version >= required_version
      true
    else
      raise Puppet::Error, "Facter 2.0.0 or greater required for Puppet to operate"
    end
  end
end

