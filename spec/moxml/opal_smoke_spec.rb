# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Moxml Opal smoke test", if: RUBY_ENGINE == "opal" do
  let(:context) { Moxml.new(:rexml) }

  it "parses XML string to document" do
    doc = context.parse("<root><child>text</child></root>")
    expect(doc).not_to be_nil
    root = doc.root
    expect(root.name).to eq("root")
    expect(root.children.first.name).to eq("child")
  end

  it "round-trips parse and serialize" do
    xml = '<person name="Alice"><age>30</age></person>'
    doc = context.parse(xml)
    serialized = doc.to_xml
    expect(serialized).to include("person")
    expect(serialized).to include("Alice")
    expect(serialized).to include("30")
  end

  it "builds XML document from scratch" do
    doc = context.create_document
    root = doc.create_element("root")
    root["attr"] = "value"
    text = doc.create_text("hello")
    root.add_child(text)
    doc.add_child(root)

    expect(doc.to_xml).to include('attr="value"')
    expect(doc.to_xml).to include("hello")
  end

  it "handles namespaces" do
    xml = '<root xmlns:ns="http://example.com"><ns:child>data</ns:child></root>'
    doc = context.parse(xml)
    expect(doc.to_xml).to include("ns:child")
  end

  it "handles CDATA sections" do
    xml = "<root><![CDATA[<script>alert('xss')</script>]]></root>"
    doc = context.parse(xml)
    expect(doc.to_xml).to include("<script>")
  end

  it "handles comments" do
    xml = "<root><!-- a comment --><child/></root>"
    doc = context.parse(xml)
    expect(doc.to_xml).to include("a comment")
  end

  it "handles processing instructions" do
    xml = '<?xml version="1.0"?><?pi-target pi-data?><root/>'
    doc = context.parse(xml)
    serialized = doc.to_xml
    expect(serialized).to include("pi-target")
  end
end
