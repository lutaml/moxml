# frozen_string_literal: true

require "spec_helper"
require_relative "shared_examples"

RSpec.describe Moxml::NativeAttachment::Native do
  it_behaves_like "an attachment backend"

  it "stores attachments outside native object instance variables" do
    attachments = described_class.new
    native = Object.new

    attachments.set(native, :entity_refs, ["amp"])

    aggregate_failures do
      expect(attachments.get(native, :entity_refs)).to eq(["amp"])
      expect(native.instance_variables).to be_empty
    end
  end

  it "registers one finalizer per native object that clears sidecar storage" do
    attachments = described_class.new
    native = Object.new
    other_native = Object.new
    finalizers = {}.compare_by_identity

    expect(ObjectSpace).to receive(:define_finalizer)
      .with(native, kind_of(Proc)).once do |object, finalizer|
        finalizers[object] = finalizer
      end
    expect(ObjectSpace).to receive(:define_finalizer)
      .with(other_native, kind_of(Proc)).once do |object, finalizer|
        finalizers[object] = finalizer
      end

    attachments.set(native, :entity_refs, ["amp"])
    attachments.set(native, :doctype, "html")
    attachments.set(other_native, :entity_refs, ["lt"])

    native_id = native.object_id
    data = attachments.instance_variable_get(:@data)
    registered = attachments.instance_variable_get(:@finalizer_registered)

    aggregate_failures do
      expect(data).to have_key(native_id)
      expect(registered).to have_key(native_id)
    end

    finalizers.fetch(native).call

    aggregate_failures do
      expect(data).not_to have_key(native_id)
      expect(registered).not_to have_key(native_id)
      expect(attachments.get(other_native, :entity_refs)).to eq(["lt"])
    end
  end
end
