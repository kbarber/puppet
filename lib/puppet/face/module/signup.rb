# encoding: UTF-8

Puppet::Face.define(:module, '1.0.0') do
  action(:signup) do
    summary "Signup user"
    description <<-HEREDOC
      Signs up the user to the forge.
    HEREDOC
    returns "TODO"

    examples <<-EOT
      Signup user:

      $ puppet module signup
      TODO
    EOT

    when_invoked do |options|
      Puppet::ModuleTool.set_option_defaults options
      Puppet::ModuleTool::Applications::Signup.run(Puppet::Forge.new("PMT", self.version), options)
    end

    when_rendering :console do |result|
      result.inspect
    end
  end

end
