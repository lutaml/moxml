# frozen_string_literal: true

RSpec.shared_examples "an attachment backend" do
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
end
