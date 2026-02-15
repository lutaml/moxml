# frozen_string_literal: true
require 'rspec'
require 'moxml'

RSpec.describe "REXML Adapter Isolated Test" do
  let(:rexml_context) { Moxml.new(:rexml) }

  describe "text extraction behavior" do
    it "extracts simple text correctly" do
      xml = <<~XML
        <root>Hello World</root>
      XML
      
      doc = rexml_context.parse(xml.dup)
      text = doc.root.text
      
      expect(text).to eq("Hello World")
    end

    it "demonstrates BMJBMJ concatenation issue - should NOT add spaces" do
      xml = <<~XML
        <root>
          <journal>BMJ</journal>
          <journal>BMJ</journal>
        </root>
      XML
      
      doc = rexml_context.parse(xml.dup)
      text = doc.root.text
      
      puts "REXML output for BMJBMJ: '#{text}'"
      # This should FAIL to demonstrate the round-trip issue
      # Other adapters produce: "BMJBMJ"
      # REXML currently produces: "BMJ BMJ" (with space)
      # For round-trip compatibility, REXML should produce "BMJBMJ"
      expect(text).to eq("BMJBMJ")
    end

    it "demonstrates mixed case transition issue - should NOT add spaces" do
      xml = <<~XML
        <root>
          <issn>0959-8138</issn>
          <publisher>BMJ</publisher>
          <author>j</author>
        </root>
      XML
      
      doc = rexml_context.parse(xml.dup)
      text = doc.root.text
      
      puts "REXML output for mixed case: '#{text}'"
      # This should FAIL to demonstrate the round-trip issue
      # Other adapters produce: "0959-8138BMJj"
      # REXML currently produces: "0959-8138 BMJ j" (with spaces)
      # For round-trip compatibility, REXML should produce "0959-8138BMJj"
      expect(text).to eq("0959-8138BMJj")
    end

    it "demonstrates digit transition issue - should NOT add spaces" do
      xml = <<~XML
        <root>
          <volume>324</volume>
          <issue>i7342</issue>
          <page>pg880</page>
          <id>11950738</id>
        </root>
      XML
      
      doc = rexml_context.parse(xml.dup)
      text = doc.root.text
      
      puts "REXML output for digits: '#{text}'"
      # This should FAIL to demonstrate the round-trip issue
      # Other adapters produce: "324i7342pg88011950738"
      # REXML currently produces: "324 i7342 pg880 11950738" (with spaces)
      # For round-trip compatibility, REXML should produce "324i7342pg88011950738"
      expect(text).to eq("324i7342pg88011950738")
    end

    it "demonstrates word boundary issue - should NOT add spaces" do
      xml = <<~XML
        <root>
          <article-type>version-of-record</article-type>
          <title>Primary</title>
        </root>
      XML
      
      doc = rexml_context.parse(xml.dup)
      text = doc.root.text
      
      puts "REXML output for word boundaries: '#{text}'"
      # This should FAIL to demonstrate the round-trip issue
      # Other adapters produce: "version-of-recordPrimary"
      # REXML currently produces: "version-of-record Primary" (with space)
      # For round-trip compatibility, REXML should produce "version-of-recordPrimary"
      expect(text).to eq("version-of-recordPrimary")
    end

    it "demonstrates complex mixed content issue - should NOT add spaces" do
      xml = <<~XML
        <root>
          <section>Primary</section>
          <year>190</year>
          <page>102</page>
          <id>18219355357</id>
        </root>
      XML
      
      doc = rexml_context.parse(xml.dup)
      text = doc.root.text
      
      puts "REXML output for complex mixed: '#{text}'"
      # This should FAIL to demonstrate the round-trip issue
      # Other adapters produce: "Primary19010218219355357"
      # REXML currently produces: "Primary 190 102 18219355357" (with spaces)
      # For round-trip compatibility, REXML should produce "Primary19010218219355357"
      expect(text).to eq("Primary19010218219355357")
    end

    it "demonstrates all patterns together - should NOT add spaces" do
      xml = <<~XML
        <root>
          <journal>BMJ</journal>
          <journal>BMJ</journal>
          <issn>0959-8138</issn>
          <publisher>BMJ</publisher>
          <author>j</author>
          <volume>324</volume>
          <issue>i7342</issue>
          <page>pg880</page>
          <id>11950738</id>
          <article-type>version-of-record</article-type>
          <section>Primary</section>
          <year>190</year>
          <page>102</page>
          <id>18219355357</id>
        </root>
      XML
      
      doc = rexml_context.parse(xml.dup)
      text = doc.root.text
      
      puts "REXML output for all patterns: '#{text}'"
      # This should FAIL to demonstrate the round-trip issue
      # Other adapters produce: "BMJBMJ0959-8138BMJj324i7342pg88011950738version-of-recordPrimary19010218219355357"
      # REXML currently produces: "BMJ BMJ 0959-8138 BMJ j 324 i7342 pg880 11950738 version-of-record Primary 190 102 18219355357" (with spaces)
      # For round-trip compatibility, REXML should produce the concatenated version
      expect(text).to eq("BMJBMJ0959-8138BMJj324i7342pg88011950738version-of-recordPrimary19010218219355357")
    end
  end
end
