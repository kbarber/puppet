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
      TODO

      Publish a module inside an existing module:
      $ puppet module publish
      TODO
    EOT

    arguments "[<module_file>]"

    when_invoked do |*args|
      options = args.pop
      if options.nil? or args.length > 1 then
        raise ArgumentError, "puppet module publish only accepts 0 or 1 arguments"
      end

      module_file = args.first

      # If no module file was passed, try and do a build action on the current
      # directory.
      if module_file.nil?
        module_file = Puppet::Face[:module, '1.0.0'].build(Dir.pwd)
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

      result = forge.publish_module(File.open(module_file))
      result
    end

    when_rendering :console do |result|
      "Module submitted for publishing: #{result.inspect}"
    end
  end

end
