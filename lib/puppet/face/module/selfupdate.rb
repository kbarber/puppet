Puppet::Face.define(:module, '1.0.0') do
  action(:selfupdate) do
    summary "Update version of the Puppet module face"
    description <<-EOT
      TODO
    EOT

    returns "TODO"

    examples <<-EOT
      TODO
    EOT

    when_invoked do |opts|
      options = {:force => true}.merge(opts)
      Puppet::ModuleTool.set_option_defaults options
      install(options)
    end

    when_rendering :console do |return_value|
      if return_value[:result] == :failure
        Puppet.err(return_value[:error][:multiline])
        exit 1
      else
        return_value[:install_dir]
      end
    end

  end

  def install(options)
    forge = Puppet::Forge.new("PMT", self.version)
    install_dir = Puppet::ModuleTool::InstallDirectory.new(Pathname.new(options[:target_dir]))
    # Puppet::ModuleTool::Applications::Upgrader.new(name, Puppet::Forge.new("PMT", self.version), options).run
    installer = Puppet::ModuleTool::Applications::Installer.new('puppetlabs-moduleface', forge, install_dir, options)
    installer.run
  end
end
