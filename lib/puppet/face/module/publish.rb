Puppet::Face.define(:module, '1.0.0') do
  action(:publish) do
    summary "Publish to the forge"
    description <<-EOT
      Publishes a module to the forge
    EOT

    returns <<-EOT
      TODO
    EOT

    examples <<-EOT
      Publish a module by specifying the file name:

      $ puppet module publish johnsmith-mymodule-1.0.0.tar.gz
      Module submitted for publishing

      Publish a module by providing a directory:

      $ puppet module publish /home/johnsmith/johnsmith-mymodule
      Building /home/johnsmith/johnsmith-mymodule
      Module submitted for publishing

      Publish a module inside an existing module:

      $ puppet module publish
      Building /home/johnsmith/johnsmith-mymodule
      Module submitted for publishing
    EOT

    arguments "[<module_path>]"

    when_invoked do |*args|
      options = args.pop
      if options.nil? or args.length > 1 then
        raise ArgumentError, "puppet module publish only accepts 0 or 1 arguments"
      end

      module_path = args.first

      # If no module file was passed, try and do a build action on the current
      # directory. If the module file is actually a directory, try doing a
      # build action on the directory.
      if module_path.nil?
        module_path = Puppet::Face[:module, '1.0.0'].build(Dir.pwd)
      elsif File.directory?(module_path)
        module_path = Puppet::Face[:module, '1.0.0'].build(module_path)
      end

      # Depending on whether there is a credentials file, attempt token auth
      # or http basic auth.
      if File.exists?(Puppet[:forge_credentials])
        token = nil
        username = nil
        File.open(Puppet[:forge_credentials], 'r') do |file|
          creds = PSON.parse(file.read)
          token = creds['authentication_token']
          username = creds['username']
        end

        forge = Puppet::Forge.new(
          :consumer_name => "PMT",
          :consumer_semver => self.version,
          :username => username,
          :authentication_token => token
        )
      else
        puts "Credentials file does not exist, falling back to basic auth."
        puts "See 'puppet help module login' for more details."
        username = Puppet::Util::Terminal.prompt "Username: "
        password = Puppet::Util::Terminal.prompt "Password: ", :silent => true

        forge = Puppet::Forge.new(
          :consumer_name => "PMT",
          :consumer_semver => self.version,
          :username => username,
          :password => password
        )
      end

      result = forge.publish_module(File.open(module_path))
      result
    end

    when_rendering :console do |result|
      "Module submitted for publishing"
    end
  end

end
