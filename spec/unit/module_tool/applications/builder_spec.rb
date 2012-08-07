require 'spec_helper'
require 'puppet/module_tool/applications'
require 'puppet_spec/modules'

describe Puppet::ModuleTool::Applications::Builder, :fails_on_windows => true do
  subject { Puppet::ModuleTool::Applications::Builder }

  #let(:build_path) { Pathname.new('/zzz/home/foo/dev/mine-mymodule') }
  let(:build_path) { Pathname.new('mine-mymodule') }
  let(:builder) do
    subject.new(build_path)
  end

  before :each do
    Puppet::ModuleTool.stubs(:find_module_root).returns(build_path)
  end

  context "initialization" do
    it "should support path name and no options" do
      subject.new(build_path)
    end
  end

  context "#run" do
    before :each do
      builder.stubs(:load_modulefile!)
      builder.stubs(:create_directory)
      builder.stubs(:copy_contents)
      builder.stubs(:add_metadata)
      Puppet.stubs(:notice)
      builder.stubs(:targzip_file)
    end

    it 'should return a relative pathname object' do
      builder.run.should == Pathname.new('foobar')
    end
  end

  context '#filename' do
    it 'should return filename with extension from metadata release_name' do
      metadata = stub(:release_name => 'mine-mymodule')
      builder.expects(:metadata).returns(metadata)
      builder.filename('tar.gz').should == 'mine-mymodule.tar.gz'
    end
  end
end
