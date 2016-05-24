#! /usr/bin/env ruby
require 'spec_helper'
require 'puppet_spec/files'

describe Puppet::Transaction::Report do
  describe "when using the indirector" do
    after do
      Puppet.settings.stubs(:use)
    end

    it "should be able to delegate to the :processor terminus" do
      Puppet::Transaction::Report.indirection.stubs(:terminus_class).returns :processor

      terminus = Puppet::Transaction::Report.indirection.terminus(:processor)

      Facter.stubs(:value).returns "host.domain.com"

      report = Puppet::Transaction::Report.new("apply")

      terminus.expects(:process).with(report)

      Puppet::Transaction::Report.indirection.save(report)
    end
  end

  # TODO: Wait, does this even work? It looks like it just inspects the top-level object
  describe "when dumping to YAML" do
    it "should not contain TagSet objects" do
      resource = Puppet::Resource.new(:notify, "Hello")
      ral_resource = resource.to_ral
      status = Puppet::Resource::Status.new(ral_resource)

      log = Puppet::Util::Log.new(:level => :info, :message => "foo")

      report = Puppet::Transaction::Report.new("apply")
      report.add_resource_status(status)
      report << log

      expect(YAML.dump(report)).to_not match('Puppet::Util::TagSet')
    end
  end

  describe "inference checking" do
    include PuppetSpec::Files
    require 'puppet/configurer'

    def run_catalogs(catalog1, catalog2, noop1 = false, noop2 = false, &block)
      last_run_report = nil

      Puppet::Transaction::Report.indirection.expects(:save).twice.with do |report, x|
        last_run_report = report
        true
      end

      Puppet[:report] = true
      Puppet[:noop] = noop1

      configurer = Puppet::Configurer.new
      configurer.run :catalog => catalog1
      last_report = last_run_report.dup

      yield block if block

      Puppet::Transaction::Report.any_instance.expects(:return_last_report).returns(last_report)

      Puppet[:noop] = noop2

      configurer = Puppet::Configurer.new
      configurer.run :catalog => catalog2
      return last_run_report
    end

    def new_blank_catalog
      Puppet::Resource::Catalog.new("testing", Puppet.lookup(:environments).get(Puppet[:environment]))
    end

    def new_catalog(resources = [])
      new_cat = new_blank_catalog
      [resources].flatten.each do |resource|
        new_cat.add_resource(resource)
      end
      new_cat
    end

    describe "for agent runs that contain" do
      it "notifies with catalog change" do
        catalog1 = new_catalog(Puppet::Type.type(:notify).new(:title => "testing",
                                                              :message => "foo"))
        catalog2 = new_catalog(Puppet::Type.type(:notify).new(:title => "testing",
                                                              :message => "foobar"))
        report = run_catalogs(catalog1, catalog2)

        expect(report.status).to eq("changed")

        param = report.resource_statuses["Notify[testing]"].parameters["message"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>true,
                                           "remediated_change"=>true,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>true,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>true,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>true,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>true,
                                           "pre_event_value_differs_from_last" => true,
                                         })
      end

      it "notifies with no catalog change" do
        catalog1 = new_catalog(Puppet::Type.type(:notify).new(:title => "testing",
                                                              :message => "foo"))
        report = run_catalogs(catalog1, catalog1)

        expect(report.status).to eq("changed")

        param = report.resource_statuses["Notify[testing]"].parameters["message"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>true,
                                           "remediated_change"=>true,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>false,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>true,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>true,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => true,
                                         })
      end

      it "new file resource" do
        file = tmpfile("test_file")
        catalog2 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff"))
        report = run_catalogs(new_catalog, catalog2)

        expect(report.status).to eq("changed")

        param = report.resource_statuses["File[#{file}]"].parameters["ensure"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>false,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>true,
                                           "puppet_change_noop"=>false,
                                           "managed"=>false,
                                           "previously_managed"=>false,
                                           "has_previous_data"=>false,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end

      pending "removal of a file resource" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff"))

        report = run_catalogs(catalog1, new_catalog)

        expect(report.status).to eq("unchanged")

        param = report.resource_statuses["File[#{file}]"].parameters["content"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>true,
                                           "newly_managed"=>true,
                                           "newly_unmanaged"=>true,

                                           "puppet_change"=>true,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>true,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>true,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end

      pending "file with a title change" do
        file1 = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file1,
                                                            :content => "mystuff"))
        file2 = tmpfile("test_file")
        catalog2 = new_catalog(Puppet::Type.type(:file).new(:title => file2,
                                                            :content => "mystuff"))

        report = run_catalogs(catalog1, catalog2)

        expect(report.status).to eq("changed")

        param = report.resource_statuses["File[#{file1}]"].parameters["content"]
        # TODO
        expect(param["inference"]).to eq({"puppet_change"=>true})

        param = report.resource_statuses["File[#{file2}]"].parameters["content"]
        # TODO
        expect(param["inference"]).to eq({"puppet_change"=>true})
      end

      pending "file with a namevar (path) only change" do
        file1 = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => 'foo',
                                                            :path => file1,
                                                            :content => "mystuff"))

        file2 = tmpfile("test_file")
        catalog2 = new_catalog(Puppet::Type.type(:file).new(:title => 'foo',
                                                            :path => file2,
                                                            :content => "mystuff"))

        report = run_catalogs(catalog1, catalog2)

        expect(report.status).to eq("changed")

        param = report.resource_statuses["File[foo]"].parameters["path"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>true,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>true,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>true,
                                           "has_previous_event"=>true,
                                           "has_previous_data"=>true,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>true,
                                           "pre_event_value_differs_from_last" => false,
                                           "pending_remediation"=>false,
                                         })
      end

      it "file with no catalog change" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff"))

        report = run_catalogs(catalog1, catalog1)

        expect(report.status).to eq("unchanged")

        param = report.resource_statuses["File[#{file}]"].parameters["content"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>false,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>false,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>false,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end

      it "file with a new parameter" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff"))
        catalog2 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff",
                                                            :loglevel => :debug))

        report = run_catalogs(catalog1, catalog2)

        expect(report.status).to eq("unchanged")

        param = report.resource_statuses["File[#{file}]"].parameters["loglevel"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>true,
                                           "newly_managed"=>true,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>false,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>false,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>false,
                                           "agent_value_change"=>true,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end

      it "file with a removed parameter" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff",
                                                            :loglevel => :debug))
        catalog2 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff"))

        report = run_catalogs(catalog1, catalog2)

        expect(report.status).to eq("unchanged")

        param = report.resource_statuses["File[#{file}]"].parameters["loglevel"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>true,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>true,

                                           "puppet_change"=>false,
                                           "puppet_change_noop"=>false,
                                           "managed"=>false,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>false,
                                           "agent_value_change"=>true,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end

      it "file with a new content property" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file))
        catalog2 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff"))

        report = run_catalogs(catalog1, catalog2)

        expect(report.status).to eq("changed")

        param = report.resource_statuses["File[#{file}]"].parameters["content"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>true,
                                           "newly_managed"=>true,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>false,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>false,
                                           "has_previous_data"=>false,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>false,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => false,
                                         })

        param = report.resource_statuses["File[#{file}]"].parameters["ensure"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>false,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>true,
                                           "puppet_change_noop"=>false,
                                           "managed"=>false,
                                           "previously_managed"=>false,
                                           "has_previous_data"=>false,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end

      pending "file with a property no longer managed" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff"))
        catalog2 = new_catalog(Puppet::Type.type(:file).new(:title => file))

        report = run_catalogs(catalog1, catalog2)

        expect(report.status).to eq("unchanged")

        param = report.resource_statuses["File[#{file}]"].parameters["content"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>true,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>true,

                                           "puppet_change"=>false,
                                           "puppet_change_noop"=>false,
                                           "managed"=>false,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>true,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>true,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end

      it "file with no catalog change, but file changed between runs" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff"))

        report = run_catalogs(catalog1, catalog1) do
          File.open(file, 'w') do |f|
            f.puts "some content"
          end
        end

        expect(report.status).to eq("changed")

        param = report.resource_statuses["File[#{file}]"].parameters["content"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>true,
                                           "remediated_change"=>true,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>false,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>true,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => true,
                                         })
      end

      it "file with catalog change, but file changed between runs that matched catalog change" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff"))
        catalog2 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "some content"))

        report = run_catalogs(catalog1, catalog2) do
          File.open(file, 'w') do |f|
            f.write "some content"
          end
        end

        expect(report.status).to eq("unchanged")

        param = report.resource_statuses["File[#{file}]"].parameters["content"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>true,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>true,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>false,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>false,
                                           "agent_value_change"=>true,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end

      it "file with catalog change, but file changed between runs that did not match catalog change" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff"))
        catalog2 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "some different content"))

        report = run_catalogs(catalog1, catalog2) do
          File.open(file, 'w') do |file|
            file.write "some content"
          end
        end

        expect(report.status).to eq("changed")

        param = report.resource_statuses["File[#{file}]"].parameters["content"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>true,
                                           "remediated_change"=>true,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>true,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>true,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>true,
                                           "pre_event_value_differs_from_last" => true,
                                         })
      end

      it "file with catalog change" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff"))
        catalog2 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff asdf"))

        report = run_catalogs(catalog1, catalog2)

        expect(report.status).to eq("changed")

        param = report.resource_statuses["File[#{file}]"].parameters["content"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>true,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>true,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>true,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end

      it "file with ensure property set to present" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :ensure => :present))

        report = run_catalogs(catalog1, catalog1)

        expect(report.status).to eq("unchanged")

        param = report.resource_statuses["File[#{file}]"].parameters["ensure"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>false,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>false,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>true,
                                           "has_current_event"=>false,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end

      it "file with ensure propery change file => absent" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :ensure => :file))
        catalog2 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :ensure => :absent))

        report = run_catalogs(catalog1, catalog2)

        expect(report.status).to eq("changed")

        param = report.resource_statuses["File[#{file}]"].parameters["ensure"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>true,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>true,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>true,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>true,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end

      pending "file with ensure propery change present => absent" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :ensure => :present))
        catalog2 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :ensure => :absent))

        report = run_catalogs(catalog1, catalog2)

        expect(report.status).to eq("changed")

        param = report.resource_statuses["File[#{file}]"].parameters["ensure"]
        expect(param["inference"]).to eq({
                                           # TODO: actually this shows up as an unexpected change,
                                           # because its old value shows up as ":file" in event
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>true,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>true,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>true,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>true,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end


      it "file with ensure propery change absent => present" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :ensure => :absent))
        catalog2 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :ensure => :present))

        report = run_catalogs(catalog1, catalog2)

        expect(report.status).to eq("changed")

        param = report.resource_statuses["File[#{file}]"].parameters["ensure"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>true,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>true,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>true,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end

      it "new resource in catalog" do
        file = tmpfile("test_file")
        catalog2 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff asdf"))

        report = run_catalogs(new_catalog, catalog2)

        expect(report.status).to eq("changed")

        param = report.resource_statuses["File[#{file}]"].parameters["content"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>true,
                                           "newly_managed"=>true,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>false,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>false,
                                           "has_previous_data"=>false,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>false,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end

      it "exec with idempotence issue" do
        catalog1 = new_catalog(Puppet::Type.type(:exec).new(:title => "exec1",
                                                            :command => "/bin/echo foo"))

        report = run_catalogs(catalog1, catalog1)

        expect(report.status).to eq("changed")

        # Of note here, is that the main idempotence issues lives in 'returns'
        param = report.resource_statuses["Exec[exec1]"].parameters["returns"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>true,
                                           "remediated_change"=>true,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>false,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>true,
                                           "puppet_change_noop"=>false,
                                           "managed"=>false,
                                           "previously_managed"=>false,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>true,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => true,
                                         })
      end

      it "exec with no idempotence issue" do
        # TODO: this might need windows compatiblity
        catalog1 = new_catalog(Puppet::Type.type(:exec).new(:title => "exec1",
                                                            :command => "echo foo",
                                                            :path => "/bin",
                                                            :unless => "ls"))

        report = run_catalogs(catalog1, catalog1)

        expect(report.status).to eq("unchanged")

        # Of note here, is that the main idempotence issues lives in 'returns'
        param = report.resource_statuses["Exec[exec1]"].parameters["returns"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>false,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>false,
                                           "puppet_change_noop"=>false,
                                           "managed"=>false,
                                           "previously_managed"=>false,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>false,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end

      it "noop on second run, file with no catalog change, but file changed between runs" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff"))

        # We should really run this test with noop on both runs, and noop only on the second run
        report = run_catalogs(catalog1, catalog1, false, true) do
          File.open(file, 'w') do |f|
            f.puts "some content"
          end
        end

        expect(report.status).to eq("unchanged")

        param = report.resource_statuses["File[#{file}]"].parameters["ensure"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>false,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>false,
                                           "puppet_change_noop"=>false,
                                           "managed"=>false,
                                           "previously_managed"=>false,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>true,
                                           "has_current_event"=>false,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => false,
                                         })

        param = report.resource_statuses["File[#{file}]"].parameters["content"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>true,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>true,

                                           "catalog_changed"=>false,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>false,
                                           "puppet_change_noop"=>true,
                                           "managed"=>true,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => true,
                                         })
      end

      it "noop on first run, file with no catalog change, but file changed between runs" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff"))

        # We should really run this test with noop on both runs, and noop only on the second run
        report = run_catalogs(catalog1, catalog1, true, false) do
          File.open(file, 'w') do |f|
            f.puts "some content"
          end
        end

        expect(report.status).to eq("changed")

        param = report.resource_statuses["File[#{file}]"].parameters["ensure"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>true,
                                           "remediated_change"=>true,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>false,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>true,
                                           "puppet_change_noop"=>false,
                                           "managed"=>false,
                                           "previously_managed"=>false,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>true,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => true,
                                         })

        param = report.resource_statuses["File[#{file}]"].parameters["content"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>false,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>false,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>false,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end

      it "noop on both runs, file with no catalog change, but file changed between runs" do
        file = tmpfile("test_file")
        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "mystuff"))

        # We should really run this test with noop on both runs, and noop only on the second run
        report = run_catalogs(catalog1, catalog1, true, true) do
          File.open(file, 'w') do |f|
            f.puts "some content"
          end
        end

        expect(report.status).to eq("unchanged")

        # The remediated field is actually going to be ensure, since we've never really managed this before
        param = report.resource_statuses["File[#{file}]"].parameters["ensure"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>true,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>true,

                                           "catalog_changed"=>false,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>false,
                                           "puppet_change_noop"=>true,
                                           "managed"=>false,
                                           "previously_managed"=>false,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>true,
                                           "has_current_event"=>true,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => true,
                                         })

        param = report.resource_statuses["File[#{file}]"].parameters["content"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>false,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>false,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>false,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end

      it "noop on both runs, file already exists but with catalog change each time" do
        file = tmpfile("test_file")

        File.open(file, 'w') do |f|
          f.puts "some content"
        end

        catalog1 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "a"))
        catalog2 = new_catalog(Puppet::Type.type(:file).new(:title => file,
                                                            :content => "b"))

        report = run_catalogs(catalog1, catalog2, true, true)

        expect(report.status).to eq("unchanged")

        # The remediated field is actually going to be ensure, since we've never really managed this before
        param = report.resource_statuses["File[#{file}]"].parameters["ensure"]
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>false,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>false,
                                           "puppet_change_noop"=>false,
                                           "managed"=>false,
                                           "previously_managed"=>false,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>false,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => false,
                                         })

        param = report.resource_statuses["File[#{file}]"].parameters["content"]
        puts param.to_yaml
        expect(param["inference"]).to eq({
                                           "unexpected_change"=>false,
                                           "remediated_change"=>false,
                                           "pending_remediation"=>false,

                                           "catalog_changed"=>false,
                                           "newly_managed"=>false,
                                           "newly_unmanaged"=>false,

                                           "puppet_change"=>false,
                                           "puppet_change_noop"=>false,
                                           "managed"=>true,
                                           "previously_managed"=>true,
                                           "has_previous_data"=>true,
                                           "has_previous_event"=>false,
                                           "has_current_event"=>false,
                                           "agent_value_change"=>false,
                                           "pre_event_value_differs_from_last" => false,
                                         })
      end
    end
  end
end
