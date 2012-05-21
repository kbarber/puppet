require 'fileutils'
require 'puppet/util/terminal'

module Puppet::ModuleTool
  module Applications
    class Signup < Application
      include Puppet::Util::Terminal

      def initialize(forge, options = {})
        @forge = forge
        super(options)
      end

      def run
        # Prompt for username
        # Prompt for password
        username = prompt "Username: "
        password = prompt "Password: ", :silent => true

        # Check validity:
        #   No existing user:
        #     Query for interview questions
        #     Perform interview
        #     Create user
        #     Persist API key.
        #   Existing user, bad password:
        #     Fail hard.
        #   Existing user, valid password:
        #     Persist API key.

        # TODO: retrieve form from the forge
        form = [
          { 'prompt' => 'Display Name', 'name' => 'display_name' },
          { 'prompt' => 'Email', 'name' => 'email', 'validate_as' => 'email' },
        ]

        # Lets stuff the username and password into the base hash for creation
        answers = {
          'user[username]' => username,
          'user[password]' => password,
        }

        # TODO: ask questions
        form.each do |question|
          while true
            print question['prompt'] + ': '
            answer = $stdin.readline.chomp
            case question['validate_as']
            when 'email'
              if answer =~ /@/
                answers["user[#{question['name']}]"] = answer
                break
              end
              puts 'Email address is invalid'
              next
            end
            answers["user[#{question['name']}]"] = answer
            break
          end
        end

        result = @forge.create_user(answers)

        # Create new credentials
        new_credentials = {
          'api_key' => result['authentication_token']
        }
        @credentials_file = Puppet.settings['forge_credentials']
        File.open(@credentials_file, 'w') do |file|
          file.write(new_credentials.to_yaml)
        end

        result
      end

      private

    end
  end
end
