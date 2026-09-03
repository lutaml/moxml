# frozen_string_literal: true

begin
  require "leptris"
rescue LoadError
  # Leptris gem not available - skip all specs in this file
  return
end

# Programmatic document construction relies on the C API added for the
# Moxml integration (leptris_document_create / leptris_document_set_root,
# exposed as Leptris::XML::Document.create / #root=). Released leptris
# 1.1.x does not ship it yet; skip instead of failing until the binding
# release catches up.
unless Leptris::XML::Document.respond_to?(:create)
  # String form: the adapter constant is not loaded in this branch —
  # resolving it would raise NameError before the skip applies.
  RSpec.describe "Moxml::Adapter::Leptris" do
    it "waits for a leptris release with programmatic document construction" do
      skip "requires leptris with Leptris::XML::Document.create (unreleased C API)"
    end
  end

  return
end

require "moxml/adapter/leptris"

RSpec.describe Moxml::Adapter::Leptris do
  around do |example|
    Moxml.with_config(:leptris, true, "UTF-8") do
      example.run
    end
  end

  it_behaves_like "xml adapter"

  describe "native xpath dispatch" do
    let(:ctx) { Moxml.new(:leptris) }
    let(:doc) do
      ctx.parse(<<~XML)
        <root xmlns:p="http://x.org">
          <item id="1" p:kind="a">alpha</item>
          <item id="2">beta</item>
        </root>
      XML
    end

    it "evaluates document-context queries on the native engine" do
      expect(doc.xpath("//item[@id='2']").map(&:text)).to eq(["beta"])
      expect(doc.xpath("count(//item)")).to eq(2.0)
      expect(doc.xpath("//item[@p:kind='a']").map { |n| n["id"] }).to eq(["1"])
    end

    it "falls back to the Ruby engine for attribute-node results" do
      attrs = doc.xpath("//item/@id")
      expect(attrs.map(&:name)).to eq(%w[id id])
      expect(attrs.map(&:value)).to eq(%w[1 2])
    end

    it "evaluates element-context queries on the native engine" do
      expect(doc.root.xpath(".//item").size).to eq(2)
      first_item = doc.root.children.find(&:element?)
      expect(first_item.xpath("following-sibling::*").map(&:name)).to eq(%w[item])
    end

    it "falls back to the Ruby engine for parent-axis queries from the root" do
      # The binding reports the root element parentless; moxml roots
      # it at the document
      expect(doc.root.xpath("../*").size).to eq(1)
    end

    it "falls back to the Ruby engine for the xmlns: reserved prefix" do
      expect(doc.xpath("//xmlns:item").size).to eq(0)
      prefixed = ctx.parse('<r xmlns="http://d.org"><item/></r>')
      expect(prefixed.xpath("//xmlns:item").size).to eq(1)
    end

    it "raises Moxml::XPathError for invalid expressions" do
      expect { doc.xpath("//item[") }.to raise_error(Moxml::XPathError)
    end
  end

  describe "document-level processing instructions" do
    let(:ctx) { Moxml.new(:leptris) }

    it "lists document PIs as children with the root" do
      doc = ctx.parse('<?xml version="1.0"?><?pi-prolog before?><root/><?pi-epilog after?><!-- tail -->')
      kids = doc.children.to_a

      expect(kids.map(&:class)).to eq(
        [Moxml::ProcessingInstruction, Moxml::Element,
         Moxml::ProcessingInstruction, Moxml::Comment],
      )
      expect(kids.select(&:processing_instruction?).map(&:target)).to eq(%w[pi-prolog pi-epilog])
      expect(kids[0].content).to eq("before")
      expect(doc.to_xml.index("pi-epilog")).to be > doc.to_xml.index("</root>")
      expect(doc.to_xml.index("<!-- tail -->")).to be > doc.to_xml.index("</root>")
    end

    it "round-trips tree-level PI mutations through serialization" do
      doc = ctx.parse("<root><a><?pi-original x?></a></root>")
      pi = doc.at_xpath("//a").children.to_a.find(&:processing_instruction?)
      pi.target = "renamed"
      pi.content = "changed"
      expect(doc.to_xml).to include("<?renamed changed?>")
    end

    it "adds document PIs and lists them as children" do
      doc = ctx.parse("<root/>")
      doc.add_child(doc.create_processing_instruction("added", "now"))
      expect(doc.to_xml).to include("<?added now?>")
      expect(doc.children.to_a.select(&:processing_instruction?).map(&:target)).to eq(%w[added])
    end

    it "keeps the document coherent across document-level PI mutation attempts" do
      # Divergent builds: libleptris 1.9.8 (released 1.9.32 platform
      # gems) accepts target= on parse-created document PIs; newer C
      # builds raise the descriptive contract error (leptris-ruby#92).
      # Pin the stable part — the document stays coherent either way.
      doc = ctx.parse("<?pi x?><root/>")
      pi = doc.children.to_a[0]

      begin
        pi.target = "renamed"
      rescue Leptris::XML::Error
        # rejected on this build
      end

      expect(doc.root.name).to eq("root")
      expect(doc.children.to_a.first.processing_instruction?).to be(true)
      expect(doc.to_xml).to match(/<root\s*\/?>|<root><\/root>/)
    end

    it "serializes children and document output in agreement" do
      # libleptris stores document PIs as one flat pre-root list (no
      # epilog anchoring); children and to_xml must at least agree.
      doc = ctx.parse('<?xml version="1.0"?><?pi-a 1?><root/><?pi-b 2?>')
      parts = doc.children.to_a.map { |c| "#{c.to_xml}\n" }.join
      from_document = doc.to_xml.sub(%r{\A<\?xml[^>]*\?>\n}, "")

      expect(from_document).to eq(parts)
    end

    it "matches raw Nokogiri byte-for-byte for pretty-printing (issue #129)" do
      cases = {
        minimal: %(<root><a/><b>x</b></root>),
        namespaces: %(<root xmlns="urn:a" xmlns:p="urn:p"><p:child p:attr="v" plain="w"/><other>x &amp; y</other></root>),
        attributes: %(<r a="1" b="two &lt;three&gt;" c="apos &apos;here&apos;"><e/></r>),
        mixed: %(<r>text <b>bold</b> tail<!-- c --></r>),
        cdata: %(<r><![CDATA[raw <stuff> & things]]></r>),
        deep: %(<l1><l2><l3><l4><leaf/></l4></l3></l2></l1>),
        unicode: %(<r name="Ünïcödé">日本語テキスト &amp; more</r>),
        unicode_nested: %(<r>a<b>日本</b>c</r>),
        longtext: %(<r>#{'word ' * 30}</r>),
        empty_root: %(<r/>),
        selfclosing: %(<r><a/><b/><c>t</c><d/></r>),
      }

      # leptris/leptris#636 (binding 1.9.42): child-PI lines and
      # DOCTYPE internal-subset layout match libxml2.
      if defined?(described_class::LIBXML2_LAYOUT_PARITY) && described_class::LIBXML2_LAYOUT_PARITY
        cases[:pi_child] = %(<r><?pi data?><e/></r>)
        cases[:pi_child_mixed] = %(<r>t<?pi d?><e>x</e>u</r>)
        cases[:doctype_subset] = %(<?xml version="1.0"?><!DOCTYPE r [<!ELEMENT r (#PCDATA)>]><r>t</r>)
        cases[:doctype_subset_multi] = %(<?xml version="1.0"?><!DOCTYPE r [<!ELEMENT r (#PCDATA)><!ATTLIST e a CDATA "d">]><r><e/></r>)
      end

      cases.each do |name, source|
        target = Nokogiri::XML(source).to_xml(indent: 2, encoding: "UTF-8")
        output = ctx.parse(source).to_xml(
          indent: 2, declaration: true, expand_empty: false, encoding: "UTF-8",
        )
        expect(output).to eq(target), "byte-parity failed for #{name}"
      end
    end

    it "keeps comments in element serialization with tab units (leptris-ruby#115)" do
      skip "requires the element unit fix (leptris 1.9.50+)" unless described_class::ELEMENT_UNIT_COMMENTS

      doc = ctx.parse(%(<r><a/><!-- c --></r>))
      expect(doc.root.to_xml(indent: 1, indent_text: "\t"))
        .to eq("<r>\n\t<a></a>\n\t<!-- c -->\n</r>")
    end

    it "round-trips document-level PI mutations through serialization" do
      # leptris/leptris#612: parse-created document PIs carry doc
      # linkage — the setters work and the tree round-trips.
      doc = ctx.parse("<?pi-prolog before?><root/>")
      pi = doc.children.to_a.first
      pi.target = "renamed"
      pi.content = "changed"
      expect(doc.to_xml).to include("<?renamed changed?>")
    end

    it "matches raw Nokogiri with tab units" do
      skip "requires the indent unit (leptris 1.9.45+)" unless described_class::INDENT_UNIT_SUPPORTED

      # Text-bearing children included since the engine fix for
      # leptris/leptris#658 (leptris 1.9.46). Comment children are
      # excluded: the binding's element+unit path drops them
      # (leptris-ruby#115).
      sources = [
        %(<r><a><b/></a><c><d/><e/></c></r>),
        %(<root><child>content</child><empty/></root>),
        %(<r>text <b>bold</b> tail</r>),
      ]
      sources.each do |source|
        target = Nokogiri::XML(source).to_xml(indent: 1, indent_text: "\t", encoding: "UTF-8")
        output = ctx.parse(source).to_xml(
          indent: 1, declaration: true, expand_empty: false,
          encoding: "UTF-8", indent_text: "\t"
        )
        expect(output).to eq(target), "tab parity failed for #{source}"
      end
    end

    it "drops space-only text nodes with noblanks and matches Nokogiri (issues #153/#156)" do
      sources = [
        %(<a><t>1</t>    <n/></a>), # blank filler between tags
        %(<p> leading</p>),                 # boundary space must survive
        %(<p><b>b</b> after</p>),           # element-to-text space must survive
        %(<p>trailing </p>),                # trailing space must survive
        %(<r>\n  <a>x <b>y</b> z</a>\n  <c/>\n</r>),
      ]
      recipe = {
        indent: 2, declaration: true, expand_empty: false, encoding: "UTF-8"
      }

      sources.each do |source|
        target = Nokogiri::XML(source, &:noblanks).to_xml(indent: 2, encoding: "UTF-8")

        doc = ctx.parse(source, noblanks: true)
        expect(doc.to_xml(recipe)).to eq(target), "noblanks parity failed for #{source}"

        via_nokogiri = Moxml.new(:nokogiri).parse(source, noblanks: true).to_xml(recipe)
        expect(via_nokogiri).to eq(target)
      end
    end

    it "leaves no text nodes on a noblanks tree of blank filler" do
      doc = ctx.parse(%(<a><t>1</t>    <n/></a>), noblanks: true)
      expect(doc.root.children.to_a.select(&:text?)).to be_empty
    end

    it "repairs a raw < in text position (issue #167 / leptris-ruby#131)" do
      # The engine intermittently drops the escape when parsing under
      # allocation pressure: a decoded &#x3c; serializes bare and the
      # output fails to reparse. Valid markup never puts < before a
      # non-name character, so the damage is deterministically
      # repairable in markup segments.
      repaired = described_class.normalize_serialization(
        %(<?xml version="1.0"?><r><pre>A <\n B</pre></r>\n), {}
      )
      expect(repaired).to include("A &lt;")
      expect(repaired).not_to match("A <")
    end

    it "keeps a literal < inside CDATA untouched by the repair" do
      doc = ctx.parse(%(<r><![CDATA[A < B]]></r>))
      expect(doc.to_xml).to include("<![CDATA[A < B]]>")
    end

    it "survives parse-under-allocation-pressure without emitting raw < (issue #167)" do
      xml = "<?xml version=\"1.0\"?><doc>#{%(<s><pre alt="A B">A &#x3c;\n B</pre></s>) * 10}</doc>"
      30.times do
        100.times { |j| "pressure#{j}" * 20 }
        out = ctx.parse(xml, noblanks: true).to_xml(
          declaration: true, encoding: "UTF-8", indent: 2, expand_empty: false,
        )
        expect(out).not_to match("A <"), "raw unescaped < leaked into text"
        expect(Nokogiri::XML(out, &:strict)).to be_a(Nokogiri::XML::Document)
      end
    end

    it "clears the namespace with nil — full contract (issue #164)" do
      doc = ctx.parse(%(<r xmlns="urn:clear"><c>t</c></r>))
      child = doc.root.children.first
      child.namespace = nil
      expect(child.namespace).to be_nil
      expect(doc.to_xml).to include(%(<c xmlns="">t</c>))
      reparsed = ctx.parse(doc.to_xml)
      expect(reparsed.root.children.first.namespace).to be_nil
    end

    it "does not raise clearing a namespace from a prefixed element (issue #164)" do
      # The engine cannot detach a prefix element's namespace link
      # (leptris-ruby#132); the name is unqualified and the
      # undeclaration added meanwhile.
      doc = ctx.parse(%(<r xmlns:p="urn:p"><p:c>t</p:c></r>))
      child = doc.root.children.first
      expect { child.namespace = nil }.not_to raise_error
    end

    it "refuses noblanks on readonly parses while the strip path is active" do
      # The strip mutates the tree; readonly freezes it at parse. On
      # bindings whose engine flag is libxml2-safe (probe), the flag
      # forwards at parse and no mutability is needed.
      skip "engine noblanks flag is libxml2-safe — no strip path" if described_class::ENGINE_NOBLANKS_SAFE

      expect { ctx.parse("<a/>", noblanks: true, readonly: true) }
        .to raise_error(ArgumentError, /noblanks.*mutable/)
    end

    it "reports the tracked native for a re-added document PI" do
      doc = ctx.parse("<?pi-src orig?><root/>")
      moved = doc.children.to_a[0]
      target_doc = ctx.parse("<other/>")
      target_doc.add_child(moved)

      expect(target_doc.to_xml).to include("<?pi-src orig?>")
      expect(target_doc.children.to_a.select(&:processing_instruction?).map(&:target)).to include("pi-src")
    end
  end

  describe "DTD ATTLIST defaults" do
    # libleptris 1.9.8: plain parse excludes ATTLIST defaults,
    # matching libxml2/Nokogiri/REXML; dtdattr: true opts in.
    let(:ctx) { Moxml.new(:leptris) }
    let(:dtd_xml) do
      %(<?xml version="1.0"?><!DOCTYPE doc [<!ATTLIST e9 attr CDATA "default">]><doc><e9/></doc>)
    end

    it "excludes ATTLIST defaults on plain parse" do
      doc = ctx.parse(dtd_xml)
      expect(doc.at_xpath("//e9")["attr"]).to be_nil
      expect(doc.to_xml).not_to include("attr=")
    end

    it "materializes ATTLIST defaults with dtdattr: true" do
      doc = ctx.parse(dtd_xml, dtdattr: true)
      expect(doc.at_xpath("//e9")["attr"]).to eq("default")
      expect(doc.to_xml).to include(%(attr="default"))
    end
  end

  describe "recover-path parse diagnostics" do
    let(:ctx) { Moxml.new(:leptris) }

    it "records the fatal error on non-strict parses" do
      doc = ctx.parse("<root><unclosed>", strict: false)
      expect(doc.root).to be_nil
      expect(doc.parse_errors).not_to be_empty
      expect(doc.parse_errors).to all(be_a(String))
    end

    it "answers [] on clean parses" do
      expect(ctx.parse("<root/>").parse_errors).to eq([])
    end

    it "still raises on strict parses" do
      expect { ctx.parse("<root><unclosed>") }.to raise_error(Moxml::ParseError)
    end
  end

  describe "entity-marker tracking" do
    let(:ctx) { Moxml.new(:leptris) }

    it "skips the marker split for entity-free documents" do
      doc = ctx.parse("<root>\n  <a>text</a>\n  <b/>\n</root>")
      kids = doc.root.children.to_a
      expect(kids.map(&:class)).to eq([Moxml::Text, Moxml::Element, Moxml::Text, Moxml::Element, Moxml::Text])
      expect(described_class.entity_bearing?(doc.root.native)).to be(false)
    end

    it "splits markers when the source carries entities" do
      doc = ctx.parse("<root><a>pre&nbsp;post</a></root>")
      kids = doc.at_xpath("//a").children.to_a
      expect(kids.map(&:class)).to include(Moxml::EntityReference)
      expect(described_class.entity_bearing?(doc.root.native)).to be(true)
    end

    it "returns serialized markup for entity-free documents" do
      # to_xml must not return nil when the restore scan is skipped
      doc = ctx.parse("<root><a>text</a></root>")
      expect(doc.to_xml).to include("<root>")
      expect(doc.at_xpath("//a").to_xml).to eq("<a>text</a>")
    end

    it "flips the flag when the builder mints an entity reference" do
      doc = ctx.parse("<root><a/></root>")
      expect(described_class.entity_bearing?(doc.root.native)).to be(false)

      er = doc.create_entity_reference("nbsp")
      doc.at_xpath("//a").add_child(er)
      expect(described_class.entity_bearing?(doc.root.native)).to be(true)
      expect(doc.at_xpath("//a").children.to_a.map(&:class)).to include(Moxml::EntityReference)
    end
  end
end
