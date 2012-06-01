Puppet::Face.define(:module, '1.0.0') do
  action(:login) do
    summary "Login to the forge"
    description <<-EOT
      This command persists a forge authentication token to a file, so that
      forge actions can be performed without requiring your username and
      password every time.
    EOT

    returns <<-EOT
      Path to token file.
    EOT

    # TODO: this doesn't seem to work, could be a bug in faces
    examples <<-EOT
      Login user:

      $ puppet module login
      Username: johnsmith
      Password: xxxxxx
    EOT

    when_invoked do |options|
      Puppet::ModuleTool.set_option_defaults options

      # Prompt for username & password
      username = Puppet::Util::Terminal.prompt "Username: "
      password = Puppet::Util::Terminal.prompt "Password: ", :silent => true

      forge = Puppet::Forge.new(
        :consumer_name => "PMT",
        :consumer_semver => self.version,
        :username => username,
        :password => password
      )

      # Attempt to retrieve existing token
      token = forge.token

      # Persist token to credentials file
      File.open(Puppet[:forge_credentials], 'w') do |file|
        contents = token.to_pson
        file.write(contents)
      end

      {
        :file => Puppet[:forge_credentials],
        :token => token[:authentication_token],
        :username => username,
      }
    end

    when_rendering :console do |result|
      <<-EOT.gsub(/^\s*/, '')
        User #{result[:username]} successfully authenticated.
        Token stored in file #{result[:file]}.
      EOT
    end
  end

end
