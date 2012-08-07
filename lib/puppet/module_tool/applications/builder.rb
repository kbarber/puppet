require 'fileutils'
require 'archive/tar/minitar'
require 'zlib'

module Puppet::ModuleTool
  module Applications
    class Builder < Application
      include Archive::Tar

      def initialize(path, options = {})
        @path = File.expand_path(Puppet::ModuleTool.find_module_root(path))
        @pkg_path = File.join(@path, 'pkg')
        super(options)
      end

      def run
        load_modulefile!
        create_directory
        copy_contents
        add_metadata
        Puppet.notice "Building #{@path} for release"
        targzip_file
        relative = Pathname.new(File.join(@pkg_path,
          filename('tar.gz'))).relative_path_from(Pathname.new(Dir.pwd))

        # Return the Pathname object representing the path to the release
        # archive just created. This return value is used by the module_tool
        # face build action, and displayed to on the console using the to_s
        # method.
        #
        # Example return value:
        #
        #   <Pathname:puppetlabs-apache/pkg/puppetlabs-apache-0.0.1.tar.gz>
        #
        relative
      end

      def filename(ext)
        ext.sub!(/^\./, '')
        "#{metadata.release_name}.#{ext}"
      end

      # This method creates the necessary tar.gz file from the contents of
      # the package directory.
      def targzip_file
        Dir.chdir(@pkg_path) do
          File.open(filename('tar.gz'), 'wb') do |gzip_file|
            sgz = Zlib::GzipWriter.new(gzip_file)
            tar = Minitar::Output.new(sgz)
            Dir.glob("#{metadata.release_name}/**") do |file|
              Minitar.pack_file(minitar_entry(file), tar)
            end
            tar.close
          end
        end
      end

      # Given a file name, return a hash that is compatible with
      # Archive::Tar::Minitar.pack_file.
      #
      # We do this for control, so we can simplify the way files are saved
      # in the tarball:
      # * uid and gid is set to zero
      # * No setuid, setgid or sticky bit
      # * No world writeable files
      #
      # @param file_name [String] name of file to analyze
      # @return [Hash{Symbol=>Any}] pack_file compatible hash
      def minitar_entry(file_name)
        stat = File.stat(file_name)
        entry = {
          :name => file_name,
          :uid => 0,
          :gid => 0,
          :mode => stat.mode & 0o775,
          :mtime => stat.mtime,
        }
      end

      def create_directory
        FileUtils.mkdir(@pkg_path) rescue nil
        if File.directory?(build_path)
          FileUtils.rm_rf(build_path, :secure => true)
        end
        FileUtils.mkdir(build_path)
      end

      def copy_contents
        Dir[File.join(@path, '*')].each do |path|
          case File.basename(path)
          when *Puppet::ModuleTool::ARTIFACTS
            next
          else
            FileUtils.cp_r path, build_path
          end
        end
      end

      def add_metadata
        File.open(File.join(build_path, 'metadata.json'), 'w') do |f|
          f.write(PSON.pretty_generate(metadata))
        end
      end

      def build_path
        @build_path ||= File.join(@pkg_path, metadata.release_name)
      end
    end
  end
end
