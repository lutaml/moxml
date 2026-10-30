# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"
require "tempfile"
require "opal"

RSpec.describe "Signature autoload boundary", :native_fs do
  let(:lib) { File.expand_path("../../lib", __dir__) }

  it "keeps the native signature module lazy and usable on Ruby" do
    source = <<~RUBY_CODE
      require "moxml"
      abort "signature was loaded eagerly" if $LOADED_FEATURES.any? { |path| path.end_with?("moxml/signature.rb") }
      abort "signature autoload missing" unless Moxml.autoload?(:Signature) == "moxml/signature"
      abort "signature module unavailable" unless Moxml::Signature::DSIG_NS == "http://www.w3.org/2000/09/xmldsig#"
      abort "OpenSSL unavailable" unless defined?(OpenSSL::PKey::RSA)
      puts "native signature available"
    RUBY_CODE
    output, error, status = Open3.capture3(RbConfig.ruby, "-I", lib, "-e", source)
    expect(status.success?).to be(true), error
    expect(output).to include("native signature available")
  end

  it "does not compile the native OpenSSL dependency into Opal" do
    # Compile the actual entrypoint declaration. This isolates the optional
    # signature boundary from the other modules loaded by the Opal boot file.
    declaration = File.readlines(File.join(lib, "moxml.rb"))
      .find { |line| line.include?('autoload :Signature, "moxml/signature"') }
    expect(declaration).not_to be_nil

    builder = Opal::Builder.new
    builder.append_paths(lib)
    builder.build("opal")
    builder.build_str(<<~RUBY_CODE, "signature-autoload-boundary")
      module Moxml
        #{declaration}
      end
      raise "native Signature loaded under Opal" if Moxml.const_defined?(:Signature, false)
      puts "Opal signature boundary passed"
    RUBY_CODE

    Tempfile.create(["moxml-signature-boundary", ".js"]) do |file|
      file.write(builder.to_s)
      file.flush
      output, error, status = Open3.capture3("node", file.path)
      expect(status.success?).to be(true), error
      expect(output).to include("Opal signature boundary passed")
    end
  end
end
