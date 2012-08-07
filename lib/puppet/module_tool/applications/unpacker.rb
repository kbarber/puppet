require 'pathname'
require 'tmpdir'
require 'zlib'
require 'archive/tar/minitar'

module Puppet::ModuleTool
  module Applications
    # This class is responsible for managing the unpacking of modules to their
    # relevant destination directories.
    class Unpacker < Application
      include Archive::Tar

      # Initialize the unpacker.
      #
      # @param filename [Pathname, String] filename of tar.gz file
      # @option options [String] :target_dir directory to install to
      def initialize(filename, options = {})
        @filename = Pathname.new(filename)
        @target_dir = options[:target_dir]
        super(options)

        parsed = parse_filename(@filename)
        @module_dir = Pathname.new(@target_dir) + parsed[:dir_name]
      end

      # Perform the module unpack step.
      #
      # @return [Pathname] path that module was unpacked to
      def run
        delete_existing_path(@module_dir)

        build_dir.mkpath
        begin
          untargz_file(@filename, build_dir.to_s)
          move_moduledir(build_dir.to_s, @module_dir)
        ensure
          build_dir.rmtree
        end

        @module_dir
      end

      # Obtain a suitable temporary path for building and unpacking tarballs
      #
      # @return [Pathname] path to temporary build location
      def build_dir
        filename_hash = Digest::SHA1.hexdigest(@filename.basename.to_s)
        Puppet::Forge::Cache.base_path + "tmp-unpacker-#{filename_hash}"
      end

      # Unpack a tar.gz file to a destination directory.
      #
      # @param filename [Pathname] path to tar.gz file
      # @param destdir [Pathname] path to destination directory
      def untargz_file(filename, destdir)
        file = File.open(filename)
        tgz = Zlib::GzipReader.new(file)
        Minitar.unpack(tgz, destdir.to_s)
      end

      # Given a directory, find the root directory for the unpacked module.
      #
      # Today, modules are packaged in such a way that the only directory
      # unpacked is the base directory of the module.
      #
      # @param builddir [Pathname] build directory
      # @return [Pathname] return the base directory of the module
      def unpacked_module_basedir(builddir)
        extracted = builddir.children.detect { |c| c.directory? }
      end

      # Given a builddir, find the base module dir and move it to the final
      # destination.
      #
      # @param builddir [Pathname] build directory
      # @param destdir [Pathname] destination directory
      def move_moduledir(builddir, destdir)
        basedir = unpacked_module_basedir(builddir)
        FileUtils.mv basedir, destdir
      end

      # Delete a directory if it exists.
      #
      # @param path [Pathname] path to delete
      def delete_existing_path(path)
        return unless path.exist?
        FileUtils.rm_rf(path, :secure => true)
      end
    end
  end
end
