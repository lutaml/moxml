# frozen_string_literal: true

require "spec_helper"

# Verifies that the Opal default adapter (:oga, set in Moxml::Config)
# loads correctly via the Opal-compatible oga fork. The fork's
# lib/oga.rb dispatches `require 'liboga'` to `require 'oga/native/lexer'`
# under Opal, which resolves to the pure-Ruby lexer vendored at
# vendor/opal-oga/ext/pureruby/.
RSpec.describe "Moxml Opal oga default", if: RUBY_ENGINE == "opal" do
  let(:context) { Moxml.new }

  it "defaults to :oga under Opal" do
    expect(Moxml::Config::OPAL_DEFAULT_ADAPTER).to eq(:oga)
  end

  it "parses XML through the oga adapter" do
    doc = context.parse("<root><child>text</child></root>")
    expect(doc.root.name).to eq("root")
    expect(doc.root.children.first.name).to eq("child")
  end

  it "decodes entities single-pass" do
    doc = context.parse("<root>&amp;#38;</root>")
    expect(doc.root.text).to eq("&#38;")
  end

  it "serializes back to XML" do
    xml = '<person name="Alice"><age>30</age></person>'
    doc = context.parse(xml)
    serialized = doc.to_xml
    expect(serialized).to include("person")
    expect(serialized).to include("Alice")
  end
end
