# frozen_string_literal: true

require "spec_helper"
require_relative "shared_examples"

RSpec.describe Moxml::NativeAttachment::Opal do
  it_behaves_like "an attachment backend"

  it "stores attachments in Moxml-owned instance variables" do
    attachments = described_class.new
    native = Object.new

    attachments.set(native, :entity_refs, ["amp"])

    expect(native.instance_variable_get(:@moxml_attachment_entity_refs))
      .to eq(["amp"])
  end

  it "removes the attachment instance variable on delete" do
    attachments = described_class.new
    native = Object.new

    attachments.set(native, :entity_refs, ["amp"])
    attachments.delete(native, :entity_refs)

    expect(native.instance_variable_defined?(:@moxml_attachment_entity_refs))
      .to be(false)
  end
end
