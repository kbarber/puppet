Puppet::Face.define(:module, '1.0.0') do
  action(:login) do
    summary "Login to the forge"
    description <<-HEREDOC
      Logs a user into the forge and creates necessary credentials files.
    HEREDOC
    returns "TODO"

    examples <<-EOT
      Login user:

      $ puppet module login
      Username: johnsmith
      Password:
    EOT

    when_invoked do |options|
      Puppet::ModuleTool.set_option_defaults options

      # Prompt for username
      # Prompt for password
      username = Puppet::Util::Terminal.prompt "Username: "
      password = Puppet::Util::Terminal.prompt "Password: ", :silent => true

      forge = Puppet::Forge.new(
        :consumer_name => "PMT",
        :consumer_semver => self.version,
        :username => username,
        :password => password
      )

      begin
        # Attempt to retrieve existing token
        token = forge.token

        # Persist token to credentials file
        # TODO: abstract or not?
        File.open(Puppet[:forge_credentials], 'w') do |file|
          file.write(token.to_pson)
        end
        puts "Valid user, credentials are written ..."
        return
      rescue RuntimeError
        # TODO: handle failure ...
        {}
      end
    end

    when_rendering :console do |result|
      result.inspect
    end
  end

end
