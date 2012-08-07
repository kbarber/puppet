require 'spec_helper'
require 'puppet/module_tool/applications'
require 'puppet_spec/modules'

describe Puppet::ModuleTool::Applications::Unpacker, :fails_on_windows => true do
  subject { Puppet::ModuleTool::Applications::Unpacker }

  let(:unpacker) do
    subject.new('myusername-mytarball-1.1.1.tar.gz',
      :target_dir => '/etc/opt/puppet/modules')
  end

  context "initialization" do
    it "should support filename and basic options" do
      subject.new("myusername-mytarball-1.0.0.tar.gz",
        :target_dir => '/tmp/modules')
    end

    it "should raise ArgumentError when filename is invalid" do
      expect { subject.new("invalid.tar.gz", :target_dir => '/tmp/modules') }.
        to raise_error(ArgumentError)
    end
  end

  context "#run" do
    let(:bdir) do
      stub(:mkpath => nil, :rmtree => nil, :to_s => '/var/tmp/build_dir')
    end

    before :each do
      unpacker.stubs(:delete_existing_installation_or_abort!)
      unpacker.stubs(:build_dir).returns(bdir)
      unpacker.stubs(:untargz_file)
      unpacker.stubs(:move_moduledir)
    end

    it 'should return a parsed module_dir' do
      unpacker.run.should == Pathname.new('/etc/opt/puppet/modules/mytarball')
    end

    it 'always remove the build directory' do
      unpacker.stubs(:untargz_file).raises(Exception)
      bdir.expects(:rmtree)
      expect { unpacker.run }.to raise_error
    end
  end

  context "#build_dir" do
    it 'should return a hashed path using forge cache path' do
      Puppet::Forge::Cache.expects(:base_path).
        returns(Pathname.new('/var/cache/modules'))
      unpacker.build_dir.should == Pathname.new('/var/cache/modules/tmp-unpacker-94efabf61c9fb23e07689aa053f117bf53433f84')
    end
  end

  context '#untargz_file' do
    it 'should unpack files' do
      file = stub()
      File.expects(:open).returns(file)
      tgz = stub()
      Zlib::GzipReader.expects(:new).with(file).returns(tgz)
      Archive::Tar::Minitar.expects(:unpack).with(tgz, '/untar/destination')
      unpacker.untargz_file(Pathname.new('/tmp/file.tar.gz'),
        Pathname.new('/untar/destination'))
    end
  end

  context '#unpacked_module_basedir' do
    it 'should return the first directory in the builddir' do
      basedir = Pathname.new('/test/base/dir')
      subdir = Pathname.new('/test/base/dir/foo')
      subdir.expects(:directory?).returns(true)
      basedir.expects(:children).returns([subdir])
      unpacker.unpacked_module_basedir(basedir).should == Pathname.new('/test/base/dir/foo')
    end

    it 'should return nil if there is no sub directory' do
      basedir = Pathname.new('/test/base/dir')
      subdir = Pathname.new('/test/base/dir/foo')
      subdir.expects(:directory?).returns(false)
      basedir.expects(:children).returns([subdir])
      unpacker.unpacked_module_basedir(basedir).should == nil
    end
  end

  context '#move_moduledir' do
    it 'should move base dir of module into destination' do
      builddir = Pathname.new('/my/module/base')
      basedir = Pathname.new('/my/module/base/dir')
      destdir = Pathname.new('/etc/puppet/modules/destdir')
      unpacker.expects(:unpacked_module_basedir).with(builddir).
        returns(basedir)
      FileUtils.expects(:mv).with(basedir, destdir)
      unpacker.move_moduledir(builddir, destdir)
    end
  end

  context '#delete_existing_path' do
    it 'should safely remove an existing path' do
      path = Pathname.new('/foo/bar/baz')
      path.expects(:exist?).returns(true)
      FileUtils.expects(:rm_rf).with(path, :secure => true)
      unpacker.delete_existing_path(path)
    end

    it 'should not remove an existing path' do
      path = Pathname.new('/foo/bar/baz')
      path.expects(:exist?).returns(false)
      FileUtils.expects(:rm_rf).never
      unpacker.delete_existing_path(path)
    end
  end
end
