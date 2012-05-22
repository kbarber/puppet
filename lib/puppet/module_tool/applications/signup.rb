require 'fileutils'
require 'puppet/util/terminal'

module Puppet::ModuleTool
  module Applications
    class Signup < Application
      def initialize(version, opts = {})
        # TODO: need a better way of getting this version
        @version = version
        super(opts)
      end

      def run
        # Prompt for username
        # Prompt for password
        username = Puppet::Util::Terminal.prompt "Username: "
        password = Puppet::Util::Terminal.prompt "Password: ", :silent => true

        # Check validity:

        forge = Puppet::Forge.new(
          :consumer_name => "PMT",
          :consumer_semver => @version,
          :username => username,
          :password => password
        )

        begin
          token = forge.token

          #   Existing user, valid password:
          #     Persist API key.
          File.open(Puppet[:forge_credentials], 'w') do |file|
            file.write(token.to_yaml)
          end
          puts "User exists, writing credentials"
          return
        rescue RuntimeError
          #   No existing user:
          #     Query for interview questions
          #     Perform interview
          #     Create user
          #     Persist API key.
          #   Existing user, bad password:
          #     Fail hard.

          forge = Puppet::Forge.new(
            :consumer_name => "PMT",
            :consumer_semver => @version
          )

          form = forge.user_form

          # TODO: retrieve form from the forge
          #form = [
          #  { 'prompt' => 'Display Name', 'name' => 'display_name' },
          #  { 'prompt' => 'Email', 'name' => 'email', 'validate_as' => 'email' },
          #]

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

          result = forge.create_user(answers)

          # Create new credentials
          new_credentials = {
            'api_key' => result['authentication_token']
          }
          credentials_file = Puppet.settings['forge_credentials']
          File.open(credentials_file, 'w') do |file|
            file.write(new_credentials.to_yaml)
          end

          result
        end

      end

    end
  end
end
