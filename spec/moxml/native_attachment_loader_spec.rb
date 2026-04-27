# frozen_string_literal: true

require "open3"
require "rbconfig"
require "spec_helper"

RSpec.describe "NativeAttachment loader" do
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

  it "registers backend implementations with autoload" do
    stdout, stderr, status = Open3.capture3(
      ruby,
      "-I",
      lib_dir,
      "-e",
      <<~'RUBY',
        require "moxml/native_attachment"

        puts !!Moxml::NativeAttachment.autoload?(:Opal)
        puts !!Moxml::NativeAttachment.autoload?(:Native)
      RUBY
    )

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("true\ntrue\n")
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

        puts !!Moxml::NativeAttachment.autoload?(:Native)
        puts Moxml::NativeAttachment.new.backend.class
        puts $LOADED_FEATURES.grep(%r{/native_attachment/native\.rb\z}).empty?
      RUBY
    )

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("true\nMoxml::NativeAttachment::Opal\ntrue\n")
  end
end
