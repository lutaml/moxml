# frozen_string_literal: true

RSpec.describe "Namespace URI validation" do
  let(:context) { Moxml.new }
  let(:doc) { context.create_document }
  let(:element) { doc.create_element("test") }

  describe "RFC 3986 URI-reference validation" do
    context "with valid absolute URIs" do
      %w[
        http://example.com
        https://www.w3.org/2001/XMLSchema
        urn:isbn:12345
        ftp://ftp.is.co.za/rfc/rfc1808.txt
        mailto:John.Doe@example.com
        mailto:bar
        tel:+1-816-555-1212
        zarquon://example.org/namespace
        http://example.org/namespace#apples
        data:text/plain;base64,SGVsbG8=
        tag:example.com,2000:test
      ].each do |uri|
        it "accepts #{uri.inspect}" do
          expect { element.add_namespace("ns", uri) }.not_to raise_error
        end
      end
    end

    context "with valid relative URI-references" do
      %w[
        my-custom-ns
        ../relative
        namespaces/zaphod
        path/to/resource
        hello%20world
      ].each do |uri|
        it "accepts #{uri.inspect}" do
          expect { element.add_namespace("ns", uri) }.not_to raise_error
        end
      end
    end

    context "with valid fragment-only references" do
      %w[
        #fragment
        #beeblebrox
      ].each do |uri|
        it "accepts #{uri.inspect}" do
          expect { element.add_namespace("ns", uri) }.not_to raise_error
        end
      end
    end

    context "with invalid URIs" do
      [
        "invalid uri",
        "has space",
        "two  spaces",
      ].each do |uri|
        it "rejects #{uri.inspect}" do
          expect do
            element.add_namespace("ns", uri)
          end.to raise_error(Moxml::NamespaceError, /Invalid URI/)
        end
      end
    end

    context "with control characters" do
      [
        "invalid\x00uri",
        "bad\x01char",
        "control\x1Fchar",
      ].each do |uri|
        it "rejects URI containing control characters" do
          expect do
            element.add_namespace("ns", uri)
          end.to raise_error(Moxml::NamespaceError)
        end
      end
    end
  end

  describe "empty URI constraint" do
    it "accepts empty URI for default namespace undeclaration" do
      expect { element.add_namespace(nil, "") }.not_to raise_error
    end

    it "rejects empty URI for prefixed namespace declarations" do
      expect do
        element.add_namespace("xs", "")
      end.to raise_error(Moxml::NamespaceError, /empty URI/)
    end
  end
end
