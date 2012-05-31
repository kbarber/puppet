Puppet::Face.define(:module, '1.0.0') do
  action(:publish) do
    summary "Publish to the forge"
    description <<-HEREDOC
      Publishes a module to the forge
    HEREDOC
    returns "TODO"

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
        raise ArgumentError, "puppet module publish only accepts 1 or 0 arguments"
      end
      Puppet::ModuleTool.set_option_defaults options

      module_file = args.pop
      if module_file.nil?
        puts "Building current package ..."
        builder = Puppet::ModuleTool::Applications::Builder.new(Dir.pwd)
        module_file = builder.run
      end

      if File.exists?(Puppet[:forge_credentials])
        token = nil
        File.open(Puppet[:forge_credentials], 'r') do |file|
          creds = PSON.parse(file.read)
          token = creds['authentication_token']
        end

        forge = Puppet::Forge.new(
          :consumer_name => "PMT",
          :consumer_semver => self.version,
          :auth_token => token
        )
      else
        username = Puppet::Util::Terminal.prompt "Username: "
        password = Puppet::Util::Terminal.prompt "Password: ", :silent => true

        forge = Puppet::Forge.new(
          :consumer_name => "PMT",
          :consumer_semver => self.version,
          :username => username,
          :password => password
        )
      end

      begin
        result = forge.module_publish(File.open(module_file))
        result.body
      rescue RuntimeError => e
        # TODO: handle failure ...
        {}
      end
    end

    when_rendering :console do |result|
      result.inspect
    end
  end

end
