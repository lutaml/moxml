# frozen_string_literal: true

require "rspec"
require "moxml"

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

      # This should FAIL to demonstrate the round-trip issue
      # Other adapters produce: "BMJBMJ0959-8138BMJj324i7342pg88011950738version-of-recordPrimary19010218219355357"
      # REXML currently produces: "BMJ BMJ 0959-8138 BMJ j 324 i7342 pg880 11950738 version-of-record Primary 190 102 18219355357" (with spaces)
      # For round-trip compatibility, REXML should produce concatenated version
      expect(text).to eq("BMJBMJ0959-8138BMJj324i7342pg88011950738version-of-recordPrimary19010218219355357")
    end

    it "demonstrates specific round-trip failure patterns - BMJ.v" do
      xml = <<~XML
        <root>
          <journal>BMJ</journal>
          <volume>v</volume>
          <number>324</number>
        </root>
      XML

      doc = rexml_context.parse(xml.dup)
      text = doc.root.text

      # Based on actual adapter behavior: both nokogiri and rexml produce "BMJv324"
      # The test expectation was wrong - should expect "BMJv324" not "BMJ.v324"
      expect(text).to eq("BMJv324")
    end

    it "demonstrates specific round-trip failure patterns - i7342.pg" do
      xml = <<~XML
        <root>
          <issue>i7342</issue>
          <page>pg880</page>
        </root>
      XML

      doc = rexml_context.parse(xml.dup)
      text = doc.root.text

      # Based on actual adapter behavior: both nokogiri and rexml produce "i7342pg880"
      # The test expectation was wrong - should expect "i7342pg880" not "i7342.pg880"
      expect(text).to eq("i7342pg880")
    end

    it "demonstrates specific round-trip failure patterns - 190102" do
      xml = <<~XML
        <root>
          <year>190</year>
          <page>102</page>
        </root>
      XML

      doc = rexml_context.parse(xml.dup)
      text = doc.root.text

      # Based on round-trip failure: expected "190102" but got "190 102"
      expect(text).to eq("190102")
    end

    it "demonstrates round-trip failure pattern - bmj BMJ" do
      xml = <<~XML
        <root>
          <journal>bmj</journal>
          <journal>BMJ</journal>
        </root>
      XML

      doc = rexml_context.parse(xml.dup)
      text = doc.root.text

      # Based on round-trip failure: expected "bmjBMJ" but got "bmj BMJ"
      expect(text).to eq("bmjBMJ")
    end

    it "demonstrates round-trip failure pattern - 8138 BMJ" do
      xml = <<~XML
        <root>
          <issn>8138</issn>
          <publisher>BMJ</publisher>
        </root>
      XML

      doc = rexml_context.parse(xml.dup)
      text = doc.root.text

      # Based on round-trip failure: expected "8138BMJ" but got "8138 BMJ"
      expect(text).to eq("8138BMJ")
    end

    it "demonstrates round-trip failure pattern - BMJ.v 324" do
      xml = <<~XML
        <root>
          <journal>BMJ</journal>
          <volume>v</volume>
          <number>324</number>
        </root>
      XML

      doc = rexml_context.parse(xml.dup)
      text = doc.root.text

      # Based on actual adapter behavior: both nokogiri and rexml produce "BMJv324"
      # The test expectation was wrong - should expect "BMJv324" not "BMJ.v324"
      expect(text).to eq("BMJv324")
    end

    it "demonstrates round-trip failure pattern - 7342 880" do
      xml = <<~XML
        <root>
          <issue>7342</issue>
          <page>880</page>
        </root>
      XML

      doc = rexml_context.parse(xml.dup)
      text = doc.root.text

      # Based on round-trip failure: expected "7342880" but got "7342 880"
      expect(text).to eq("7342880")
    end

    it "demonstrates round-trip failure pattern - version-of-record Primary" do
      xml = <<~XML
        <root>
          <article-type>version-of-record</article-type>
          <section>Primary</section>
        </root>
      XML

      doc = rexml_context.parse(xml.dup)
      text = doc.root.text

      # Based on round-trip failure: expected "version-of-recordPrimary" but got "version-of-record Primary"
      expect(text).to eq("version-of-recordPrimary")
    end
  end
end
