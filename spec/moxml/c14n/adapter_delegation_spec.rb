# frozen_string_literal: true

require "spec_helper"
require "moxml/c14n"

CORPUS = {
  "cdata content becomes escaped text" => [
    "<doc><![CDATA[a < b]]>tail</doc>",
    "<doc>a &lt; btail</doc>",
  ],
  "prefixed and unprefixed attributes" => [
    %(<doc xmlns:p="urn:p"><e p:x="1" y="2"/></doc>),
    %(<doc xmlns:p="urn:p"><e y="2" p:x="1"></e></doc>),
  ],
  "reserved xml:* attributes keep the xml prefix" => [
    %(<doc xml:base="http://a/b/" xml:lang="en" xml:space="preserve"><e xml:id="i1"/></doc>),
    %(<doc xml:base="http://a/b/" xml:lang="en" xml:space="preserve"><e xml:id="i1"></e></doc>),
  ],
  "default namespace transitions" => [
    %(<doc xmlns="urn:a"><e xmlns=""/><e xmlns="urn:a"/></doc>),
    %(<doc xmlns="urn:a"><e xmlns=""></e><e></e></doc>),
  ],
  "namespace redeclaration" => [
    %(<doc xmlns:m="urn:m"><m:e xmlns:m="urn:m2"/></doc>),
    %(<doc xmlns:m="urn:m"><m:e xmlns:m="urn:m2"></m:e></doc>),
  ],
  "prefixed namespace ordering" => [
    %(<r xmlns:z="urn:z" xmlns:a="urn:a" b="2" a="1"/>),
    %(<r xmlns:a="urn:a" xmlns:z="urn:z" a="1" b="2"></r>),
  ],
  "entities stay escaped" => [
    "<doc>a &amp; b &lt; c</doc>",
    "<doc>a &amp; b &lt; c</doc>",
  ],
}.freeze

RSpec.describe "Moxml::C14n cross-adapter canonicalization" do
  # Every installed adapter must answer identical canonical bytes: the
  # Ruby reference path (Inclusive10) is shared, but attribute/namespace
  # reporting differs per adapter, and two adapters additionally
  # delegate the default shape to a native engine (leptris in C,
  # nokogiri via libxml2).
  describe "byte-identical canonical form across adapters" do
    Moxml::Adapter::AVAILABLE_ADAPTERS.each do |adapter_name|
      context "with the #{adapter_name} adapter" do
        let(:ctx) { Moxml.new(adapter_name) }

        CORPUS.each do |label, (input, expected)|
          it "canonicalizes #{label}" do
            root = ctx.parse(input).root
            expect(Moxml::C14n.canonicalize_inclusive10(root)).to eq(expected)
            expect(Moxml::C14n.canonicalize(root)).to eq(expected)
          end
        end
      end
    end
  end

  describe "document-level nodes keep document order" do
    # oga surfaces the XML declaration as a <?xml?> PI and keeps the
    # separator space in PI content; ox/headed_ox drop PI content on
    # parse. Both are pre-existing parse-layer divergences, out of
    # scope here.
    let(:adapters) { Moxml::Adapter::AVAILABLE_ADAPTERS - %i[oga ox headed_ox] }

    it "canonicalizes a leading PI before the root element" do
      adapters.each do |adapter_name|
        doc = Moxml.new(adapter_name)
          .parse(%(<?xml version="1.0"?><?render mode="x"?><doc><e/></doc>))
        expect(Moxml::C14n.canonicalize(doc))
          .to eq(%(<?render mode="x"?>\n<doc><e></e></doc>))
      end
    end
  end

  describe "native delegation" do
    adapters_with_native = %i[leptris nokogiri].select do |name|
      Moxml::Adapter::AVAILABLE_ADAPTERS.include?(name)
    end

    adapters_with_native.each do |adapter_name|
      context "with the #{adapter_name} adapter" do
        let(:adapter_class) do
          Moxml::Adapter.const_get(adapter_name.to_s.split("_").map(&:capitalize).join)
        end

        it "passes the byte-safety probe" do
          expect(adapter_class.native_c14n_byte_safe?).to be(true)
        end

        it "engages the native path for the default shape" do
          doc = Moxml.new(adapter_name)
            .parse(%(<doc xmlns="urn:d" a="1"><e>t</e></doc>))
          native = Moxml::C14n.native_inclusive10(doc.root, :inclusive10, false, [])
          expect(native).to be_a(String)
        end

        it "keeps exclusive on the Ruby engine" do
          doc = Moxml.new(adapter_name)
            .parse(%(<root xmlns:foo='urn:foo'><foo:a/></root>))
          expect(Moxml::C14n.canonicalize(doc.root, algorithm: :exclusive10))
            .to eq(Moxml::C14n.canonicalize_exclusive(doc.root))
        end

        it "keeps inclusive 1.1 on the Ruby engine" do
          doc = Moxml.new(adapter_name).parse(%(<root a="1"/>))
          expect(Moxml::C14n.canonicalize(doc.root, algorithm: :inclusive11))
            .to eq(Moxml::C14n.canonicalize_inclusive11(doc.root))
        end

        it "keeps with_comments on the Ruby engine" do
          doc = Moxml.new(adapter_name).parse(%(<doc><!-- c --><e/></doc>))
          expect(Moxml::C14n.canonicalize(doc.root, with_comments: true))
            .to eq(Moxml::C14n.canonicalize_inclusive10(doc.root,
                                                        with_comments: true))
        end
      end
    end
  end
end
