module Puppet::ModuleTool::Errors

  class SignupError < ModuleToolError; end

#  class ExistingCredentialsError < SignupError
#    def initialize(options)
#      @credentials_file = options[:credentials_file]
#      super 'Credentials already exist'
#    end
#
#    def multiline
#      message = []
#      message << "Could not signup"
#      message << "  Credentials file '#{@credentials_file}' already exists"
#      message << "    Remove existing credentials file '#{@credentials_file}' before trying again"
#      message.join("\n")
#    end
#  end
end
