# This class includes a number of utility methods for dealing with the terminal.
module Puppet::Util::Terminal
  # Attempts to determine the width of the terminal.  This is currently only
  # supported on POSIX systems, and relies on the claims of `stty` (or `tput`).
  #
  # Inspired by code from Thor; thanks wycats!
  # @return [Number] The column width of the terminal.  Defaults to 80 columns.
  def self.width
    if Puppet.features.posix?
      result = %x{stty size 2>/dev/null}.split[1] ||
               %x{tput cols 2>/dev/null}.split[0]
    end
    return (result || '80').to_i
  rescue
    return 80
  end

  # Prompt for input on STDOUT and receive a response from a user from STDIN.
  #
  # @note Currently only Windows and Unix terminals are supported.
  # @param [String] prompt Prompt to display to the user.
  # @option opts [Boolean] :silent If true, do not echo the response to the
  #   screen. This is useful for password prompts and other secrets.
  # @return [String] The response collected from STDIN.
  # @example Prompt for a username
  #   username = Puppet::Util::Terminal.prompt "Username: "
  # @example Prompt for a password
  #   password = Puppet::Util::Terminal.prompt "Password: ", :silent => true
  # @raise [RuntimeError] If we are unable to disable echo using stty.
  def self.prompt(prompt = '', opts={})
    print prompt

    unless opts[:silent]
      STDIN.gets.chomp
    else
      # With silent, we need to handle Windows & Unix differently
      if Puppet.features.microsoft_windows?
        response = ''
        require 'Win32API'
        while char = Win32API.new("crtdll", "_getch", [ ], "L").Call do
          break if char == 10 || char == 13 # return or newline
          if char == 127 || char == 8 # backspace and delete
            response.slice!(-1, 1)
          else
            response << char.chr
          end
        end
        response
      else
        state = `stty -g`
        raise 'Could not disable echo' unless system 'stty -echo'
        response = STDIN.gets.chomp
        raise 'Could not re-enable echo' unless system "stty #{state}"
        puts
        response
      end
    end
  end

end
