# frozen_string_literal: true

RSpec.shared_examples "Moxml::Namespace" do
  describe Moxml::Namespace do
    let(:context) { Moxml.new }
    let(:doc) { context.create_document }
    let(:element) { doc.create_element("test") }

    describe "creation" do
      it "creates namespace with prefix" do
        element.add_namespace("xs", "http://www.w3.org/2001/XMLSchema")
        ns = element.namespaces.first

        expect(ns).to be_namespace
        expect(ns.prefix).to eq("xs")
        expect(ns.uri).to eq("http://www.w3.org/2001/XMLSchema")
      end

      it "creates default namespace" do
        element.add_namespace(nil, "http://example.org")
        ns = element.namespaces.first

        expect(ns.prefix).to be_nil
        expect(ns.uri).to eq("http://example.org")
      end

      it "validates URI per RFC 3986" do
        expect do
          element.add_namespace("xs", "invalid uri")
        end.to raise_error(Moxml::NamespaceError, /Invalid URI/)
      end

      it "accepts valid relative URI-references" do
        expect do
          element.add_namespace("xs", "my-custom-ns")
        end.not_to raise_error
      end

      it "rejects empty URI for prefixed namespace declarations" do
        expect do
          element.add_namespace("xs", "")
        end.to raise_error(Moxml::NamespaceError, /empty URI/)
      end
    end

    describe "string representation" do
      it "formats prefixed namespace" do
        element.add_namespace("xs", "http://www.w3.org/2001/XMLSchema")
        expect(element.namespaces.first.to_s).to eq('xmlns:xs="http://www.w3.org/2001/XMLSchema"')
      end

      it "formats default namespace" do
        element.add_namespace(nil, "http://example.org")
        expect(element.namespaces.first.to_s).to eq('xmlns="http://example.org"')
      end

      it "renders the same xml - a readme example" do
        # chainable operations
        element
          .add_namespace("dc", "http://purl.org/dc/elements/1.1/")
          .add_child(doc.create_text("content"))

        # clear node type checking
        node = doc.create_element("test")
        if node.element?
          node.add_namespace("dc", "http://purl.org/dc/elements/1.1/")
          node.add_child(doc.create_text("content"))
        end

        expect(element.to_xml).to eq(node.to_xml)
      end
    end

    describe "equality" do
      let(:ns1) { element.add_namespace("xs", "http://www.w3.org/2001/XMLSchema").namespaces.last }
      let(:ns2) { element.add_namespace("xs", "http://www.w3.org/2001/XMLSchema").namespaces.last }
      let(:ns3) { element.add_namespace("xsi", "http://www.w3.org/2001/XMLSchema-instance").namespaces.last }

      it "compares namespaces" do
        expect(ns1).to eq(ns2)
        expect(ns1).not_to eq(ns3)
      end

      it "compares with different elements" do
        other_element = doc.create_element("other")
        other_ns = other_element.add_namespace("xs", "http://www.w3.org/2001/XMLSchema").namespaces.first
        expect(ns1).to eq(other_ns)
      end
    end

    describe "in_scope_namespaces" do
      it "returns namespaces declared on the element itself" do
        element.add_namespace("xs", "http://www.w3.org/2001/XMLSchema")
        element.add_namespace("xsi", "http://www.w3.org/2001/XMLSchema-instance")

        in_scope = element.in_scope_namespaces
        prefixes = in_scope.map(&:prefix)
        uris = in_scope.map(&:uri)

        expect(prefixes).to include("xs", "xsi")
        expect(uris).to include(
          "http://www.w3.org/2001/XMLSchema",
          "http://www.w3.org/2001/XMLSchema-instance",
        )
      end

      it "inherits namespaces from ancestor elements" do
        root = doc.create_element("root")
        root.add_namespace("xs", "http://www.w3.org/2001/XMLSchema")
        child = doc.create_element("child")
        root.add_child(child)

        in_scope = child.in_scope_namespaces
        prefixes = in_scope.map(&:prefix)

        expect(prefixes).to include("xs")
      end

      it "collects namespaces from multiple ancestor levels" do
        root = doc.create_element("root")
        root.add_namespace("xs", "http://www.w3.org/2001/XMLSchema")
        middle = doc.create_element("middle")
        middle.add_namespace("dc", "http://purl.org/dc/elements/1.1/")
        root.add_child(middle)
        leaf = doc.create_element("leaf")
        middle.add_child(leaf)

        in_scope = leaf.in_scope_namespaces
        prefixes = in_scope.map(&:prefix)

        expect(prefixes).to include("xs", "dc")
      end

      it "closest ancestor wins for duplicate prefixes" do
        root = doc.create_element("root")
        root.add_namespace("ns", "http://example.org/old")
        child = doc.create_element("child")
        child.add_namespace("ns", "http://example.org/new")
        root.add_child(child)

        in_scope = child.in_scope_namespaces
        ns_match = in_scope.find { |ns| ns.prefix == "ns" }

        expect(ns_match.uri).to eq("http://example.org/new")
      end

      it "includes default namespace" do
        root = doc.create_element("root")
        root.add_namespace(nil, "http://example.org/default")
        child = doc.create_element("child")
        root.add_child(child)

        in_scope = child.in_scope_namespaces
        default_ns = in_scope.find { |ns| ns.prefix.nil? }

        expect(default_ns).not_to be_nil
        expect(default_ns.uri).to eq("http://example.org/default")
      end

      it "returns empty array for element with no namespaces" do
        lonely = doc.create_element("lonely")
        expect(lonely.in_scope_namespaces).to eq([])
      end

      it "returns empty array for document root with no namespace declarations" do
        root = doc.create_element("root")
        doc.add_child(root)
        expect(root.in_scope_namespaces).to eq([])
      end
    end

    describe "inheritance" do
      it "does not inherit parent namespaces" do
        # https://stackoverflow.com/a/67347081
        root = doc.create_element("root")
        root.namespace = { "xs" => "http://www.w3.org/2001/XMLSchema" }
        child = doc.create_element("child")
        root.add_child(child)

        expect(child.namespace).to be_nil
      end

      it "inherits default parent namespaces" do
        root = doc.create_element("root")
        root.namespace = { nil => "http://www.w3.org/2001/XMLSchema" }
        child = doc.create_element("child")
        root.add_child(child)

        expect(child.namespace.prefix).to be_nil
        expect(child.namespace.uri).to eq("http://www.w3.org/2001/XMLSchema")
      end

      it "overrides parent namespace" do
        root = doc.create_element("root")
        root.namespace = { "ns" => "http://example.org/1" }
        child = doc.create_element("child")
        child.namespace = { "ns" => "http://example.org/2" }
        root.add_child(child)

        expect(root.namespace.uri).to eq("http://example.org/1")
        expect(child.namespace.uri).to eq("http://example.org/2")
      end
    end
  end
end
