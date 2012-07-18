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

      path = args.first
      if path.nil?
        pkg_path = Puppet::Face[:module, '1.0.0'].build
      elsif FileTest.directory?(path)
        pkg_path = Puppet::Face[:module, '1.0.0'].build(path)
      elsif FileTest.file?(path)
        pkg_path = path
      else
        raise "Path #{path} is not valid"
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

      result = forge.publish_module(File.open(pkg_path))
      result
    end

    when_rendering :console do |result|
      "Module submitted for publishing"
    end
  end

end
