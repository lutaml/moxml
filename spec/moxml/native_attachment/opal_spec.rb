# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::NativeAttachment::Opal do
  subject(:attachments) { described_class.new }

  let(:native) { Object.new }
  let(:other_native) { Object.new }

  it "stores and reads attachments by native object and key" do
    attachments.set(native, :entity_refs, ["amp"])
    attachments.set(native, :doctype, "html")
    attachments.set(other_native, :entity_refs, ["lt"])

    aggregate_failures do
      expect(attachments.get(native, :entity_refs)).to eq(["amp"])
      expect(attachments.get(native, :doctype)).to eq("html")
      expect(attachments.get(other_native, :entity_refs)).to eq(["lt"])
      expect(attachments.key?(native, :entity_refs)).to be(true)
      expect(attachments.key?(native, :missing)).to be(false)
    end
  end

  it "preserves explicit nil attachments" do
    attachments.set(native, :xml_declaration, nil)

    aggregate_failures do
      expect(attachments.get(native, :xml_declaration)).to be_nil
      expect(attachments.key?(native, :xml_declaration)).to be(true)
    end
  end

  it "deletes attachments" do
    attachments.set(native, :entity_refs, ["amp"])

    expect(attachments.delete(native, :entity_refs)).to eq(["amp"])

    aggregate_failures do
      expect(attachments.get(native, :entity_refs)).to be_nil
      expect(attachments.key?(native, :entity_refs)).to be(false)
      expect(attachments.delete(native, :entity_refs)).to be_nil
    end
  end

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
