Puppet::Face.define(:module, '1.0.0') do
  action(:logout) do
    summary "Logout of the forge"
    description <<-EOT
      This command removes your persistent authentication token from the local
      forge credentials file.
    EOT

    returns <<-EOT
      TODO
    EOT

    # TODO: this doesn't seem to work, could be a bug in faces
    examples <<-EOT
      Logout user:

      $ puppet module logout
      Credential file removed.
    EOT

    when_invoked do |options|
      Puppet::ModuleTool.set_option_defaults options

      # Persist token to credentials file
      if File.exists?(Puppet[:forge_credentials])
        File.delete(Puppet[:forge_credentials])
        return(Puppet[:forge_credentials])
      else
        return false
      end
    end

    when_rendering :console do |result|
      if result
        return "Credential file removed."
      else
        return "Credential file not removed or does not exist."
      end
    end
  end

end
