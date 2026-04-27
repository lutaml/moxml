# frozen_string_literal: true

require "open3"
require "rbconfig"
require "spec_helper"

RSpec.describe Moxml::NativeAttachment do
  let(:attachments) { described_class.new }
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

  it "delegates storage calls to the configured backend" do
    backend = Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def get(native, key)
        @calls << [:get, native, key]
        :stored_value
      end

      def set(native, key, value)
        @calls << [:set, native, key, value]
      end

      def key?(native, key)
        @calls << [:key?, native, key]
        true
      end

      def delete(native, key)
        @calls << [:delete, native, key]
        :stored_value
      end
    end.new
    attachments = described_class.new(backend: backend)

    expect(attachments.get(native, :entity_refs)).to eq(:stored_value)
    attachments.set(native, :entity_refs, ["amp"])
    expect(attachments.key?(native, :entity_refs)).to be(true)
    expect(attachments.delete(native, :entity_refs)).to eq(:stored_value)

    expect(backend.calls).to eq([
      [:get, native, :entity_refs],
      [:set, native, :entity_refs, ["amp"]],
      [:key?, native, :entity_refs],
      [:delete, native, :entity_refs],
    ])
  end

  it "supports the Opal implementation contract directly" do
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      "-I",
      File.expand_path("../../lib", __dir__),
      "-e",
      <<~'RUBY',
        require "moxml/native_attachment/opal"

        attachments = Moxml::NativeAttachment::Opal.new
        native = Object.new
        other_native = Object.new

        attachments.set(native, :entity_refs, ["amp"])
        attachments.set(native, :xml_declaration, nil)
        attachments.set(other_native, :entity_refs, ["lt"])

        unless attachments.get(native, :entity_refs) == ["amp"]
          raise "missing entity refs"
        end

        unless attachments.key?(native, :xml_declaration)
          raise "nil attachment not tracked"
        end

        unless attachments.get(other_native, :entity_refs) == ["lt"]
          raise "attachments leaked between objects"
        end

        unless attachments.delete(native, :entity_refs) == ["amp"]
          raise "delete did not return value"
        end

        raise "delete did not clear key" if attachments.key?(native, :entity_refs)
      RUBY
    )

    expect(status.success?).to be(true), [stdout, stderr].join
  end

  it "uses the selected runtime backend" do
    expected_class = if RUBY_ENGINE == "opal"
                       Moxml::NativeAttachment::Opal
                     else
                       Moxml::NativeAttachment::Native
                     end

    expect(attachments.backend).to be_a(expected_class)
  end
end
