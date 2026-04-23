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
      'require "moxml"; puts Moxml::NativeAttachment.name',
    )

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("Moxml::NativeAttachment\n")
  end

  it "loads NativeAttachment through the direct compatibility entrypoint" do
    stdout, stderr, status = Open3.capture3(
      ruby,
      "-I",
      lib_dir,
      "-e",
      'require "moxml/native_attachment"; puts Moxml::NativeAttachment.name',
    )

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("Moxml::NativeAttachment\n")
  end

  it "uses literal runtime-specific requires in the top-level loader" do
    source = File.read(File.expand_path("../../lib/moxml.rb", __dir__))

    aggregate_failures do
      expect(source).to include('if RUBY_ENGINE == "opal"')
      expect(source).to include('require_relative "moxml/native_attachment/opal"')
      expect(source).to include('require_relative "moxml/native_attachment/native"')
    end
  end
end
