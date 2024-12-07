RSpec.shared_examples 'Moxml::Element' do
  describe Moxml::Element do
    let(:context) { Moxml.new }
    let(:doc) { context.create_document }
    let(:element) { doc.create_element("test") }

    describe "name handling" do
      it "gets name" do
        expect(element.name).to eq("test")
      end

      it "sets name" do
        element.name = "new_name"
        expect(element.name).to eq("new_name")
      end
    end

    describe "attributes" do
      before { element["id"] = "123" }

      it "sets attribute" do
        expect(element["id"]).to eq("123")
      end

      it "gets attribute" do
        expect(element.attribute("id")).to be_a(Moxml::Attribute)
        expect(element.attribute("id").value).to eq("123")
      end

      it "gets all attributes" do
        element["class"] = "test"
        expect(element.attributes.size).to eq(2)
        expect(element.attributes.map(&:name)).to contain_exactly("id", "class")
      end

      it "removes attribute" do
        element.remove_attribute("id")
        expect(element["id"]).to be_nil
      end

      it "handles special characters" do
        element["special"] = '< > & " \''
        expect(element.to_xml).to include('special="&lt; &gt; &amp; &quot; \'')
      end
    end

    describe "namespaces" do
      it "adds namespace" do
        element.add_namespace("x", "http://example.org")
        expect(element.namespaces.size).to eq(1)
        expect(element.namespace.prefix).to eq("x")
        expect(element.namespace.uri).to eq("http://example.org")
      end

      it "sets namespace" do
        ns = element.add_namespace("x", "http://example.org").namespace
        element.namespace = ns
        expect(element.namespace).to eq(ns)
      end

      it "adds default namespace" do
        element.add_namespace(nil, "http://example.org")
        expect(element.namespace.prefix).to be_nil
        expect(element.namespace.uri).to eq("http://example.org")
      end
    end

    describe "content manipulation" do
      it "sets text content" do
        element.text = "content"
        expect(element.text).to eq("content")
      end

      it "appends text" do
        element.text = "first"
        element.add_child("second")
        expect(element.text).to eq("firstsecond")
      end

      it "sets inner HTML" do
        element.inner_html = "<child>text</child>"
        expect(element.children.size).to eq(1)
        expect(element.children.first.name).to eq("child")
        expect(element.children.first.text).to eq("text")
      end
    end

    describe "node manipulation" do
      it "adds child element" do
        child = doc.create_element("child")
        element.add_child(child)
        expect(element.children.first).to eq(child)
      end

      it "adds child text" do
        element.add_child("text")
        expect(element.text).to eq("text")
      end

      it "adds mixed content" do
        element.add_child("text")
        element.add_child(doc.create_element("child"))
        element.add_child("more")
        expect(element.to_xml).to include("text<child></child>more")
      end
    end
  end
end
