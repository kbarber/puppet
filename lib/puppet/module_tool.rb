# encoding: UTF-8
# Load standard libraries
require 'pathname'
require 'fileutils'
require 'puppet/util/colors'

# Define tool
module Puppet
  module ModuleTool
    extend Puppet::Util::Colors

    # Directory and names that should not be checksummed.
    FULL_MODULE_NAME_PATTERN = /\A([^-\/|.]+)[-|\/](.+)\z/
    REPOSITORY_URL = Puppet.settings[:module_repository]

    # Return the +username+ and +modname+ for a given +full_module_name+, or raise an
    # ArgumentError if the argument isn't parseable.
    def self.username_and_modname_from(full_module_name)
      if matcher = full_module_name.match(FULL_MODULE_NAME_PATTERN)
        return matcher.captures
      else
        raise ArgumentError, "Not a valid full name: #{full_module_name}"
      end
    end

    def self.set_option_defaults(options)
      sep = File::PATH_SEPARATOR
      if options[:target_dir]
        options[:target_dir] = File.expand_path(options[:target_dir])
      end

      prepend_target_dir = !! options[:target_dir]

      options[:modulepath] ||= Puppet.settings[:modulepath]
      options[:environment] ||= Puppet.settings[:environment]
      options[:modulepath] = "#{options[:target_dir]}#{sep}#{options[:modulepath]}" if prepend_target_dir
      Puppet[:modulepath] = options[:modulepath]
      Puppet[:environment] = options[:environment]

      options[:target_dir] = options[:modulepath].split(sep).first
      options[:target_dir] = File.expand_path(options[:target_dir])
    end
  end
end

# Load remaining libraries
require 'puppet/module_tool/errors'
require 'puppet/module_tool/applications'
require 'puppet/forge/cache'
require 'puppet/forge'
