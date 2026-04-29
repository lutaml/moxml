# frozen_string_literal: true

require "open3"
require "rbconfig"
require "spec_helper"

RSpec.describe Moxml::NativeAttachment do
  describe ".default_backend" do
    it "uses the Opal backend under Opal" do
      stub_const("RUBY_ENGINE", "opal")

      expect(described_class.default_backend).to be_a(described_class::Opal)
    end

    it "uses the native backend under non-Opal Ruby engines" do
      stub_const("RUBY_ENGINE", "ruby")

      expect(described_class.default_backend).to be_a(described_class::Native)
    end
  end

  describe "facade" do
    subject(:attachments) { described_class.new }

    let(:native) { Object.new }

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

      expect(backend.calls).to eq(
        [
          [:get, native, :entity_refs],
          [:set, native, :entity_refs, ["amp"]],
          [:key?, native, :entity_refs],
          [:delete, native, :entity_refs],
        ],
      )
    end

    it "uses the selected runtime backend" do
      expected_class = if RUBY_ENGINE == "opal"
                         described_class::Opal
                       else
                         described_class::Native
                       end

      expect(attachments.backend).to be_a(expected_class)
    end
  end

  describe "loader" do
    let(:lib_dir) { File.expand_path("../../lib", __dir__) }
    let(:ruby) { RbConfig.ruby }

    it "loads NativeAttachment through the top-level moxml entrypoint" do
      stdout, stderr, status = Open3.capture3(
        ruby,
        "-I",
        lib_dir,
        "-e",
        'require "moxml"; puts Moxml::NativeAttachment.new.respond_to?(:set)',
      )

      expect(status.success?).to be(true), stderr
      expect(stdout).to eq("true\n")
    end

    it "loads NativeAttachment through the internal facade file" do
      stdout, stderr, status = Open3.capture3(
        ruby,
        "-I",
        lib_dir,
        "-e",
        'require "moxml/native_attachment"; puts Moxml::NativeAttachment.new.respond_to?(:set)',
      )

      expect(status.success?).to be(true), stderr
      expect(stdout).to eq("true\n")
    end

    it "registers backend implementations with require-style autoload paths" do
      stdout, stderr, status = Open3.capture3(
        ruby,
        "-I",
        lib_dir,
        "-e",
        <<~RUBY,
          require "moxml/native_attachment"

          puts Moxml::NativeAttachment.autoload?(:Opal)
          puts Moxml::NativeAttachment.autoload?(:Native)
        RUBY
      )

      expect(status.success?).to be(true), stderr
      expect(stdout).to eq(
        "moxml/native_attachment/opal\n" \
        "moxml/native_attachment/native\n",
      )
    end

    it "loads the native backend lazily when selected" do
      stdout, stderr, status = Open3.capture3(
        ruby,
        "-I",
        lib_dir,
        "-e",
        <<~'RUBY',
          require "moxml/native_attachment"

          puts $LOADED_FEATURES.grep(%r{/native_attachment/native\.rb\z}).empty?
          puts Moxml::NativeAttachment.new.backend.class
          puts !$LOADED_FEATURES.grep(%r{/native_attachment/native\.rb\z}).empty?
          puts $LOADED_FEATURES.grep(%r{/native_attachment/opal\.rb\z}).empty?
        RUBY
      )

      expect(status.success?).to be(true), stderr
      expect(stdout).to eq(
        "true\n" \
        "Moxml::NativeAttachment::Native\n" \
        "true\n" \
        "true\n",
      )
    end

    it "does not load the native backend when Opal is selected" do
      stdout, stderr, status = Open3.capture3(
        ruby,
        "-I",
        lib_dir,
        "-e",
        <<~'RUBY',
          Object.send(:remove_const, :RUBY_ENGINE)
          RUBY_ENGINE = "opal"

          require "moxml/native_attachment"

          puts Moxml::NativeAttachment.autoload?(:Native)
          puts Moxml::NativeAttachment.new.backend.class
          puts $LOADED_FEATURES.grep(%r{/native_attachment/native\.rb\z}).empty?
        RUBY
      )

      expect(status.success?).to be(true), stderr
      expect(stdout).to eq(
        "moxml/native_attachment/native\n" \
        "Moxml::NativeAttachment::Opal\n" \
        "true\n",
      )
    end
  end
end
