require "spec_helper"
require "timecop"

def v4_event
  event_xml = '<event href="/ovirt-engine/api/events/16359" id="16359">
  <description>VM new_vm configuration was updated by admin@internal-authz.</description>
  <code>35</code>
  <correlation_id>4e787afc-ed42-4193-82a0-66943860d142</correlation_id>
  <custom_id>-1</custom_id>
  <flood_rate>30</flood_rate>
  <origin>oVirt</origin>
  <severity>normal</severity>
  <time>2017-05-07T15:45:05.485+03:00</time>
  <cluster href="/ovirt-engine/api/clusters/504ae500-3476-450e-8243-f6df0f7f7acf" id="504ae500-3476-450e-8243-f6df0f7f7acf"/>
  <data_center href="/ovirt-engine/api/datacenters/b60b3daa-dcbd-40c9-8d09-3fc08c91f5d1" id="b60b3daa-dcbd-40c9-8d09-3fc08c91f5d1"/>
  <template href="/ovirt-engine/api/templates/785e845e-baa0-4812-8a8c-467f37ad6c79" id="785e845e-baa0-4812-8a8c-467f37ad6c79"/>
  <vm href="/ovirt-engine/api/vms/78e60d40-1fd9-42e7-aa07-4ef4439b5289" id="78e60d40-1fd9-42e7-aa07-4ef4439b5289"/>
  </event>'
  event = OvirtSDK4::Reader.read(event_xml)
  ManageIQ::Providers::Redhat::InfraManager::EventFetcher.new(@ems).set_event_name!(event)
  event
end

describe ManageIQ::Providers::Redhat::InfraManager::EventCatcher::Runner do
  let(:settings) { {:flooding_monitor_enabled => false} }
  before do
    allow_any_instance_of(ManageIQ::Providers::Redhat::InfraManager).to receive_messages(:authentication_check => [true, ""])
    allow_any_instance_of(MiqWorker::Runner).to receive(:worker_initialization)
    allow_any_instance_of(MiqWorker::Runner).to receive(:worker_settings).and_return(settings)
  end

  context "api_version 4" do
    let(:ems) { FactoryGirl.create(:ems_redhat, :hostname => "hostname", :api_version => '4.1') }
    let(:catcher) { ManageIQ::Providers::Redhat::InfraManager::EventCatcher::Runner.new(:ems_id => ems.id) }

    let(:event) { v4_event }
    let(:event_dup) { event.dup.tap { |e| e.time += 0.00001 } }
    let(:event2) { event_dup.dup.tap { |e| e.code = 36 } }

    context "#event_dedup_key" do
      it "creates the same dedup key" do
        expect(catcher.event_dedup_key(event)).to eq(catcher.event_dedup_key(event_dup))
      end

      it "creates different dedup keys" do
        expect(catcher.event_dedup_key(event)).not_to eq(catcher.event_dedup_key(event2))
      end
    end

    context "#queue_event" do
      # TODO: once we have better way to initialize a runner and automatically reload before every test
      # the following code can be removed. Here the runner is forced to reload because the class level
      # settings need to be changed between tests.
      before do
        ManageIQ::Providers::Redhat::InfraManager::EventCatcher.send(:remove_const, :Runner)
        load 'app/models/manageiq/providers/redhat/infra_manager/event_catcher/runner.rb'
        Timecop.freeze(0)
      end

      after { Timecop.return }

      context "event flooding monitor is enabled" do
        let(:settings) do
          {
            :flooding_monitor_enabled   => true,
            :flooding_events_per_minute => 1
          }
        end

        it "block duplicates events by not placing it to the queue" do
          expect(EmsEvent).to receive(:add_queue).once
          catcher.queue_event(event)
          Timecop.freeze(10)
          catcher.queue_event(event_dup)
        end
      end

      context "event flooding monitor is disabled" do
        it "places every event to the queue" do
          expect(EmsEvent).to receive(:add_queue).twice
          catcher.queue_event(event)
          Timecop.freeze(10)
          catcher.queue_event(event2)
        end
      end
    end
  end
end
