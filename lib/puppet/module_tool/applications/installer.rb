require 'open-uri'
require 'pathname'
require 'fileutils'
require 'tmpdir'
require 'semver'
require 'puppet/forge'
require 'puppet/module_tool'
require 'puppet/module_tool/shared_behaviors'
require 'puppet/module_tool/install_directory'

module Puppet::ModuleTool
  module Applications
    class Installer < Application

      include Puppet::ModuleTool::Errors
      include Puppet::Forge::Errors

      def initialize(name, forge, install_dir, options = {})
        super(options)
        @action              = :install
        @environment         = Puppet::Node::Environment.new(Puppet.settings[:environment])
        @force               = options[:force]
        @name                = name
        @forge               = forge
        @install_dir         = install_dir
      end

      def run
        begin
          @source = :repository
          @module_name = @name.gsub('/', '-')
          @version = options[:version]

          results = {
            :module_name    => @module_name,
            :module_version => @version,
            :install_dir    => options[:target_dir],
          }

          @install_dir.prepare(@module_name, @version || 'latest')

          cached_paths = get_release_packages

          unless @graph.empty?
            Puppet.notice 'Installing -- do not interrupt ...'
            cached_paths.each do |hash|
              hash.each do |dir, path|
                Unpacker.new(path, @options.merge(:target_dir => dir)).run
              end
            end
          end
        rescue ModuleToolError, ForgeError => err
          results[:error] = {
            :oneline   => err.message,
            :multiline => err.multiline,
          }
        else
          results[:result] = :success
          results[:installed_modules] = @graph
        ensure
          results[:result] ||= :failure
        end

        results
      end

      include Puppet::ModuleTool::Shared

      def get_release_packages
        get_local_constraints
        get_remote_constraints(@forge)

        @graph = resolve_constraints({ @module_name => @version })

        Puppet::Forge::Cache.clean
        download_tarballs(@graph, @graph.last[:path], @forge)
      end
    end
  end
end
