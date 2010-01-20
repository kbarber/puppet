#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../spec_helper'

require 'puppet/transaction'

def without_warnings
    flag = $VERBOSE
    $VERBOSE = nil
    yield
    $VERBOSE = flag
end

describe Puppet::Transaction do
    before do
        @transaction = Puppet::Transaction.new(Puppet::Resource::Catalog.new)
    end

    it "should delegate its event list to the event manager" do
        @transaction = Puppet::Transaction.new(Puppet::Resource::Catalog.new)
        @transaction.event_manager.expects(:events).returns %w{my events}
        @transaction.events.should == %w{my events}
    end

    it "should be able to accept resource status instances" do
        resource = Puppet::Type.type(:notify).new :title => "foobar"
        status = Puppet::Resource::Status.new(resource)
        @transaction.add_resource_status(status)
        @transaction.resource_status(resource).should equal(status)
    end

    it "should be able to look resource status up by resource reference" do
        resource = Puppet::Type.type(:notify).new :title => "foobar"
        status = Puppet::Resource::Status.new(resource)
        @transaction.add_resource_status(status)
        @transaction.resource_status(resource.to_s).should equal(status)
    end

    it "should return nil when asked for a status that has not been created" do
        @transaction.resource_status("File[/foo]").should be_nil
    end

    it "should consider a resource to be failed if a status instance exists for that resource and indicates it is failed" do
        resource = Puppet::Type.type(:notify).new :name => "yayness"
        status = Puppet::Resource::Status.new(resource)
        status.failed = "some message"
        @transaction.add_resource_status(status)
        @transaction.should be_failed(resource)
    end

   it "should consider a resource to have failed dependencies if any of its dependencies are failed"

    describe "when initializing" do
        it "should create an event manager" do
            @transaction = Puppet::Transaction.new(Puppet::Resource::Catalog.new)
            @transaction.event_manager.should be_instance_of(Puppet::Transaction::EventManager)
            @transaction.event_manager.transaction.should equal(@transaction)
        end

        it "should create a resource harness" do
            @transaction = Puppet::Transaction.new(Puppet::Resource::Catalog.new)
            @transaction.resource_harness.should be_instance_of(Puppet::Transaction::ResourceHarness)
            @transaction.resource_harness.transaction.should equal(@transaction)
        end
    end

    describe "when evaluating a resource" do
        before do
            @transaction = Puppet::Transaction.new(Puppet::Resource::Catalog.new)
            @transaction.stubs(:eval_children_and_apply_resource)
            @transaction.stubs(:skip?).returns false

            @resource = stub("resource")
        end

        it "should check whether the resource should be skipped" do
            @transaction.expects(:skip?).with(@resource).returns false

            @transaction.eval_resource(@resource)
        end

        it "should eval and apply children" do
            @transaction.expects(:eval_children_and_apply_resource).with(@resource)

            @transaction.eval_resource(@resource)
        end

        it "should process events" do
            @transaction.event_manager.expects(:process_events).with(@resource)

            @transaction.eval_resource(@resource)
        end

        describe "and the resource should be skipped" do
            before do
                @transaction.expects(:skip?).with(@resource).returns true
            end

            it "should increment the 'skipped' count" do
                @transaction.eval_resource(@resource)
                @transaction.resourcemetrics[:skipped].should == 1
            end
        end
    end

    describe "when applying a resource" do
        before do
            @resource = Puppet::Type.type(:file).new :path => "/my/file"
            @status = Puppet::Resource::Status.new(@resource)

            @transaction = Puppet::Transaction.new(Puppet::Resource::Catalog.new)
            @transaction.event_manager.stubs(:queue_event)
            @transaction.resource_harness.stubs(:evaluate).returns(@status)
        end

        it "should use its resource harness to apply the resource" do
            @transaction.resource_harness.expects(:evaluate).with(@resource)
            @transaction.apply(@resource)
        end

        it "should add the resulting resource status to its status list" do
            @transaction.apply(@resource)
            @transaction.resource_status(@resource).should be_instance_of(Puppet::Resource::Status)
        end

        it "should queue any events added to the resource status" do
            @status.expects(:events).returns %w{a b}
            @transaction.event_manager.expects(:queue_event).with(@resource, "a")
            @transaction.event_manager.expects(:queue_event).with(@resource, "b")
            @transaction.apply(@resource)
        end

        it "should log and skip any resources that cannot be applied" do
            @transaction.resource_harness.expects(:evaluate).raises ArgumentError
            @resource.expects(:err)
            @transaction.apply(@resource)
            @transaction.resource_status(@resource).should be_nil
        end
    end

    describe "when generating resources" do
        it "should finish all resources" do
            generator = stub 'generator', :depthfirst? => true, :tags => []
            resource = stub 'resource', :tag => nil

            @catalog = Puppet::Resource::Catalog.new
            @transaction = Puppet::Transaction.new(@catalog)

            generator.expects(:generate).returns [resource]

            @catalog.expects(:add_resource).yields(resource)

            resource.expects(:finish)

            @transaction.generate_additional_resources(generator, :generate)
        end

        it "should skip generated resources that conflict with existing resources" do
            generator = mock 'generator', :tags => []
            resource = stub 'resource', :tag => nil

            @catalog = Puppet::Resource::Catalog.new
            @transaction = Puppet::Transaction.new(@catalog)

            generator.expects(:generate).returns [resource]

            @catalog.expects(:add_resource).raises(Puppet::Resource::Catalog::DuplicateResourceError.new("foo"))

            resource.expects(:finish).never
            resource.expects(:info) # log that it's skipped

            @transaction.generate_additional_resources(generator, :generate).should be_empty
        end

        it "should copy all tags to the newly generated resources" do
            child = stub 'child'
            generator = stub 'resource', :tags => ["one", "two"]

            @catalog = Puppet::Resource::Catalog.new
            @transaction = Puppet::Transaction.new(@catalog)

            generator.stubs(:generate).returns [child]
            @catalog.stubs(:add_resource)

            child.expects(:tag).with("one", "two")

            @transaction.generate_additional_resources(generator, :generate)
        end
    end

    describe "when skipping a resource" do
        before :each do
            @resource = stub_everything 'res'
            @catalog = Puppet::Resource::Catalog.new
            @transaction = Puppet::Transaction.new(@catalog)
        end

        it "should skip resource with missing tags" do
            @transaction.stubs(:missing_tags?).returns(true)
            @transaction.skip?(@resource).should be_true
        end

        it "should ask the resource if it's tagged with any of the tags" do
            tags = ['one', 'two']
            @transaction.stubs(:ignore_tags?).returns(false)
            @transaction.stubs(:tags).returns(tags)

            @resource.expects(:tagged?).with(*tags).returns(true)

            @transaction.missing_tags?(@resource).should be_false
        end

        it "should skip not scheduled resources" do
            @transaction.stubs(:scheduled?).returns(false)
            @transaction.skip?(@resource).should be_true
        end

        it "should skip resources with failed dependencies" do
            @transaction.stubs(:failed_dependencies?).returns(false)
            @transaction.skip?(@resource).should be_true
        end

        it "should skip virtual resource" do
            @resource.stubs(:virtual?).returns true
            @transaction.skip?(@resource).should be_true
        end
    end

    describe "when adding metrics to a report" do
        before do
            @catalog = Puppet::Resource::Catalog.new
            @transaction = Puppet::Transaction.new(@catalog)

            @report = stub 'report', :newmetric => nil, :time= => nil
        end

        [:resources, :time, :changes].each do |metric|
            it "should add times for '#{metric}'" do
                @report.expects(:newmetric).with { |m, v| m == metric }
                @transaction.add_metrics_to_report(@report)
            end
        end
    end

    describe 'when checking application run state' do
        before do
            without_warnings { Puppet::Application = Class.new(Puppet::Application) }
            @catalog = Puppet::Resource::Catalog.new
            @transaction = Puppet::Transaction.new(@catalog)
        end

        after do
            without_warnings { Puppet::Application = Puppet::Application.superclass }
        end

        it 'should return true for :stop_processing? if Puppet::Application.stop_requested? is true' do
            Puppet::Application.stubs(:stop_requested?).returns(true)
            @transaction.stop_processing?.should be_true
        end

        it 'should return false for :stop_processing? if Puppet::Application.stop_requested? is false' do
            Puppet::Application.stubs(:stop_requested?).returns(false)
            @transaction.stop_processing?.should be_false
        end

        describe 'within an evaluate call' do
            before do
                @resource = stub 'resource', :ref => 'some_ref'
                @catalog.add_resource @resource
                @transaction.stubs(:prepare)
                @transaction.sorted_resources = [@resource]
            end

            it 'should stop processing if :stop_processing? is true' do
                @transaction.expects(:stop_processing?).returns(true)
                @transaction.expects(:eval_resource).never
                @transaction.evaluate
            end

            it 'should continue processing if :stop_processing? is false' do
                @transaction.expects(:stop_processing?).returns(false)
                @transaction.expects(:eval_resource).returns(nil)
                @transaction.evaluate
            end
        end
    end

    describe "when prefetching" do
        it "should match resources by name, not title" do
            @catalog = Puppet::Resource::Catalog.new
            @transaction = Puppet::Transaction.new(@catalog)

            # Have both a title and name
            resource = Puppet::Type.type(:sshkey).create :title => "foo", :name => "bar", :type => :dsa, :key => "eh"
            @catalog.add_resource resource

            resource.provider.class.expects(:prefetch).with("bar" => resource)

            @transaction.prefetch
        end
    end
end

describe Puppet::Transaction, " when determining tags" do
    before do
        @config = Puppet::Resource::Catalog.new
        @transaction = Puppet::Transaction.new(@config)
    end

    it "should default to the tags specified in the :tags setting" do
        Puppet.expects(:[]).with(:tags).returns("one")
        @transaction.tags.should == %w{one}
    end

    it "should split tags based on ','" do
        Puppet.expects(:[]).with(:tags).returns("one,two")
        @transaction.tags.should == %w{one two}
    end

    it "should use any tags set after creation" do
        Puppet.expects(:[]).with(:tags).never
        @transaction.tags = %w{one two}
        @transaction.tags.should == %w{one two}
    end

    it "should always convert assigned tags to an array" do
        @transaction.tags = "one::two"
        @transaction.tags.should == %w{one::two}
    end

    it "should accept a comma-delimited string" do
        @transaction.tags = "one, two"
        @transaction.tags.should == %w{one two}
    end

    it "should accept an empty string" do
        @transaction.tags = ""
        @transaction.tags.should == []
    end
end
