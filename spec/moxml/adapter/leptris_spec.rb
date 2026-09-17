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

    it "evaluates attribute-node queries with proper wrappers" do
      # Native since 1.9.105 (leptris-ruby#153: ResultAttr with
      # name/value); earlier bindings returned generic nodes whose
      # #name raised, so the Ruby engine owned them.
      skip "requires native attr results (leptris 1.9.105+)" unless described_class::ATTR_RESULT_NATIVE
      attrs = doc.xpath("//item/@id")
      expect(attrs.map(&:name)).to eq(%w[id id])
      expect(attrs.map(&:value)).to eq(%w[1 2])
      expect(attrs.first).to be_a(Moxml::Attribute)
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

      shape = kids.map do |k|
        if k.processing_instruction?
          :pi
        else
          k.element? ? :element : :comment
        end
      end
      expect(shape).to eq(%i[pi element pi comment])
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
      skip "guard stood down on fixed bindings (leptris-ruby#131, 1.9.80+)" unless described_class::Serialize::RAW_LT_GUARD_ACTIVE
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

  describe "HTML parsing (leptris/leptris#659)" do
    before do
      skip "requires leptris 1.9.80+ (HTML engine mode)" unless described_class::HTML_PARSE_SUPPORTED
    end

    let(:ctx) { Moxml.new(:leptris) }

    it "synthesizes the html/body structure with lowercased names" do
      doc = ctx.parse_html(%(<DIV CLASS="x">t</DIV>))
      expect(doc.root.name).to eq("html")
      body = doc.root.children.find(&:element?)
      expect(body.name).to eq("body")
      div = body.at_xpath(".//div")
      expect(div["class"]).to eq("x")
      expect(div.text).to eq("t")
    end

    it "implies end tags for list items" do
      doc = ctx.parse_html(%(<ul><li>one<li>two</ul>))
      expect(doc.xpath("//li").map(&:text)).to eq(%w[one two])
    end

    it "keeps void elements as empty elements" do
      doc = ctx.parse_html(%(<br><img src="x.png">))
      expect(doc.xpath("//br").size).to eq(1)
      expect(doc.xpath("//img").first["src"]).to eq("x.png")
    end

    it "decodes HTML named entities into text" do
      doc = ctx.parse_html(%(<p>caf&eacute; &nbsp;&copy;</p>))
      expect(doc.at_xpath("//p").text).to eq("caf\u00e9 \u00a0\u00a9")
    end

    it "materializes boolean attributes" do
      doc = ctx.parse_html(%(<a href="/x" disabled>t</a>))
      link = doc.at_xpath("//a")
      expect(link["href"]).to eq("/x")
      expect(link["disabled"]).to eq("")
    end

    it "reads script content as raw text" do
      doc = ctx.parse_html(%(<script>if (a < b) { x("</div>"); }</script>))
      expect(doc.at_xpath("//script").text).to include("a < b")
      expect(doc.at_xpath("//script").text).to include("</div>")
    end

    it "serializes to well-formed XML that reparses strictly" do
      doc = ctx.parse_html(%(<p>a &amp; b < c</p><script>y = "</q>";</script>))
      out = doc.to_xml
      expect(out).to include("&lt;")
      reparsed = Nokogiri::XML(out, &:strict)
      expect(reparsed).to be_a(Nokogiri::XML::Document)
      expect(reparsed.errors).to be_empty
    end

    it "preserves foreign content (SVG/MathML) in HTML documents" do
      doc = ctx.parse_html(%(<p>a</p><svg viewBox="0 0 1 1"><circle r="1"/></svg><math><mi>a</mi></math>))
      body = doc.root.children.find(&:element?)
      names = body.children.select(&:element?).map(&:name)
      expect(names).to include("svg", "math")
      expect(body.at_xpath(".//circle")["r"]).to eq("1")
      expect(body.at_xpath(".//mi").text).to eq("a")
    end

    it "preserves foreignObject content Nokogiri drops (name lowercased)" do
      # WHATWG keeps foreign-content camelCase (foreignObject,
      # viewBox); the engine currently lowercases like it does HTML
      # names, but preserves the subtree — Nokogiri drops it
      # entirely. Pins current behavior; engine conformance note
      # filed for the adjust-tables.
      doc = ctx.parse_html(%(<svg><foreignObject><p>x</p></foreignObject></svg>))
      out = doc.to_xml
      expect(out).to include("<foreignobject>")
      expect(out).to include("<p>x</p>")
    end

    it "round-trips an HTML doctype with external identifiers" do
      doc = ctx.parse_html(%(<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "x.dtd"><p>a</p>))
      expect(doc.to_xml).to include(%(<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "x.dtd">))
    end

    it "preserves template element placement" do
      doc = ctx.parse_html(%(<div><template><p>t</p></template></div>))
      expect(doc.at_xpath("//template/p")&.text).to eq("t")
    end

    it "round-trips a parsed tree through mutation" do
      doc = ctx.parse_html(%(<ul><li>a<li>b</ul>))
      doc.at_xpath("//ul").add_child(doc.create_element("li"))
      expect(doc.xpath("//li").map(&:name)).to eq(%w[li li li])
    end
  end

  describe "iterparse streaming" do
    let(:ctx) { Moxml.new(:leptris) }
    let(:xml) do
      %(<catalog>#{Array.new(3) { |i| %(<record id="r#{i}"><field name="f">v#{i} &amp; x</field></record>) }.join}</catalog>)
    end

    it "yields completed top-level children with readable attributes" do
      seen = []
      ctx.iterparse(xml) { |e| seen << [e.name, e["id"]] }
      expect(seen).to eq([["record", "r0"], ["record", "r1"], ["record", "r2"]])
    end

    it "full_document yields every element in completion order" do
      seen = []
      ctx.iterparse(xml, mode: :full_document) { |e| seen << e.name }
      expect(seen).to eq(%w[field record field record field record catalog])
    end

    it "reads children, text, and serializes inside the block" do
      outs = []
      ctx.iterparse(xml) do |e|
        outs << [e.children.first["name"], e.children.first.text,
                 Nokogiri::XML(e.to_xml, &:strict).root["id"]]
      end
      expect(outs.map(&:first)).to all(eq("f"))
      expect(outs.map { |row| row[1] }).to all(match(/v\d & x/))
      expect(outs.map { |row| row[2] }).to eq(%w[r0 r1 r2])
    end

    it "streams from a file" do
      require "tmpdir"
      Dir.mktmpdir do |dir|
        path = File.join(dir, "doc.xml")
        File.write(path, xml)
        seen = []
        ctx.iterparse_file(path) { |e| seen << e["id"] }
        expect(seen).to eq(%w[r0 r1 r2])
      end
    end

    it "answers subqueries on yielded elements via the Ruby engine" do
      # Parentless elements have no document handle for the compiled
      # native eval — the gate must route them, not crash.
      seen = []
      ctx.iterparse(xml) do |e|
        seen << [e.at_xpath(".//field")["name"], e.xpath("count(.//field)")]
      end
      expect(seen).to eq([["f", 1.0]] * 3)
    end

    it "requires a block" do
      expect { ctx.iterparse(xml) }.to raise_error(ArgumentError, /block/)
    end
  end

  describe "C14n native delegation" do
    it "matches the Ruby reference byte-for-byte on the default path" do
      # Whether the NATIVE_C14N_BYTE_SAFE probe is armed (fixed
      # engine builds delegate to the C canonicalizer) or not, the
      # default-path output must equal the Ruby reference — this is
      # the safety net that lets the probe auto-adopt future builds.
      xml = %(<?xml version="1.0"?><doc xmlns:p="urn:p" xmlns="urn:d" b="2" a="1"><e p:x="v" z="w">t &amp; u</e><!-- c --></doc>)
      ctx = Moxml.new(:leptris)
      root = ctx.parse(xml).root
      expect(Moxml::C14n.canonicalize(root))
        .to eq(Moxml::C14n::Inclusive10.new.canonicalize(root))
    end
  end

  describe "wrapper lifecycle" do
    it "releases wrappers when documents are dropped (WeakMap registry)" do
      # The identity map must hold wrappers weakly: parse-and-drop
      # workloads otherwise pin wrappers, natives, and (via the
      # binding finalizer never running) the C subtrees.
      xml = %(<r>#{Array.new(50) { |i| "<e id=\"i#{i}\">x</e>" }.join}</r>)
      ctx = Moxml.new(:leptris)
      count = -> {
        n = 0
        ObjectSpace.each_object(Moxml::Element) { n += 1 }
        n
      }
      walk = ->(doc) { doc.root.children.to_a }

      GC.start
      before = count.call
      20.times do
        doc = ctx.parse(xml)
        walk.(doc)
        nil
      end
      5.times { GC.start }

      # The binding retains a constant one-document wrapper set of
      # its own; moxml must not retain beyond a couple of dropped
      # documents' worth (was: all 20 pinned under the strong map).
      expect(count.call - before).to be < 2 * 51
    end

    it "keeps wrapper identity while a document is alive" do
      ctx = Moxml.new(:leptris)
      doc = ctx.parse(%(<r><a/></r>))
      expect(doc.root.children.first).to equal(doc.root.children.first)
      GC.start
      expect(doc.root.children.first).to equal(doc.root.children.first)
    end
  end

  describe "lazy xpath result sets" do
    let(:ctx) { Moxml.new(:leptris) }
    let(:doc) do
      ctx.parse(%(<r>#{Array.new(50) { |i| "<li>#{i}</li>" }.join}</r>))
    end

    it "answers size, first, and indexing without materializing" do
      set = doc.xpath("//li")
      expect(set.size).to eq(50)
      expect(set.first.text).to eq("0")
      expect(set[10].text).to eq("10")
      expect(set[-1].text).to eq("49")
      expect(set.empty?).to be(false)
    end

    it "enumerates and wraps on demand" do
      expect(doc.xpath("//li").each.to_a.size).to eq(50)
      expect(doc.xpath("//li").to_a.map(&:name).uniq).to eq(%w[li])
    end

    it "keeps the mutating set operations working" do
      set = doc.xpath("//li")
      expect((set + set).size).to eq(100)
      expect(set.uniq_by_native.size).to eq(50)
      set << doc.create_element("li")
      expect(set.size).to eq(51)
      expect(set.last.name).to eq("li")
    end

    it "slices ranges" do
      expect(doc.xpath("//li")[0..2].size).to eq(3)
      expect(doc.xpath("//li")[5...8].map(&:text)).to eq(%w[5 6 7])
    end

    it "returns scalars and at_xpath firsts unwrapped-set" do
      expect(doc.xpath("count(//li)")).to eq(50.0)
      expect(doc.at_xpath("//li").text).to eq("0")
      expect(doc.at_xpath("//nope")).to be_nil
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
      shape = kids.map { |k| k.text? ? :text : :element }
      expect(shape).to eq(%i[text element text element text])
      expect(described_class.entity_bearing?(doc.root.native)).to be(false)
    end

    it "splits markers when the source carries entities" do
      doc = ctx.parse("<root><a>pre&nbsp;post</a></root>")
      kids = doc.at_xpath("//a").children.to_a
      expect(kids.map { |k| k.is_a?(Moxml::EntityReference) }).to include(true)
      expect(described_class.entity_bearing?(doc.root.native)).to be(true)
    end

    it "returns serialized markup for entity-free documents" do
      # to_xml must not return nil when the restore scan is skipped
      doc = ctx.parse("<root><a>text</a></root>")
      expect(doc.to_xml).to include("<root>")
      expect(doc.at_xpath("//a").to_xml).to eq("<a>text</a>")
    end

    it "validates entity_mode" do
      config = Moxml::Config.new(:leptris)
      config.entity_mode = :keep

      expect(config.entity_mode).to eq(:keep)
      expect { config.entity_mode = :invalid }.to raise_error(ArgumentError)
    end

    it "uses first-class entity references when requested on supported bindings" do
      skip "requires leptris 1.9.177" unless described_class::NATIVE_ENTITY_REFS

      keep_ctx = Moxml.new(:leptris) { |config| config.entity_mode = :keep }
      doc = keep_ctx.parse("<root><a>pre &amp; middle &lt; post</a></root>")
      children = doc.at_xpath("//a").children.to_a

      expect(children.map(&:content)).to eq(["pre ", "", " middle ", "", " post"])
      expect(children[1]).to be_a(Moxml::EntityReference)
      expect(children[1].name).to eq("amp")
      expect(children[3].name).to eq("lt")
      expect(doc.to_xml).to include("pre &amp; middle &lt; post")
    end

    it "creates a first-class entity reference on supported bindings" do
      skip "requires leptris 1.9.177" unless described_class::NATIVE_ENTITY_REFS

      keep_ctx = Moxml.new(:leptris) { |config| config.entity_mode = :keep }
      doc = keep_ctx.parse("<root><a/></root>")
      reference = doc.create_entity_reference("copy")
      doc.at_xpath("//a").add_child(reference)

      expect(reference).to be_a(Moxml::EntityReference)
      expect(reference.name).to eq("copy")
      expect(doc.to_xml).to include("&copy;")
    end

    it "keeps expansion as the default entity mode" do
      doc = Moxml.new(:leptris).parse("<root>a &amp; b</root>")

      expect(doc.root.children.first).to be_a(Moxml::Text)
      expect(doc.root.children.first.content).to eq("a & b")
    end
  end

  describe "adapter seams from the relaton migration (issue #245)" do
    let(:ctx) { Moxml.new(:leptris) }

    it "keeps parse_fragment nodes' owning document alive" do
      nodes = ctx.parse_fragment("<em>x</em>")
      element = nodes.first
      expect(element.parent_node).not_to be_nil
      GC.start
      GC.start
      expect(element.name).to eq("em")
      expect(element.text).to eq("x")
      document = element.document
      expect(document.children.first.name).to eq("m")
      expect(document.children.first.children.first.name).to eq("em")
    end

    it "inserts siblings after a text node" do
      doc = ctx.parse("<root><p>a<!--c1-->b</p></root>")
      paragraph = doc.root.children.first
      cursor = paragraph.children.first
      cursor.add_next_sibling(doc.create_text("Z"))
      expect(paragraph.to_xml).to eq("<p>aZ<!--c1-->b</p>")
    end

    it "inserts siblings before a text node" do
      doc = ctx.parse("<root><p><!--c1-->ab</p></root>")
      paragraph = doc.root.children.first
      cursor = paragraph.children.last
      cursor.add_previous_sibling(doc.create_text("Y"))
      expect(paragraph.to_xml).to eq("<p><!--c1-->Yab</p>")
    end
  end

  describe "to_binding is defined regardless of the native layer (issue #217)" do
    it "is the identity for binding nodes" do
      ctx = Moxml.new(:leptris)
      doc = ctx.parse(%(<r><a x="1"><b/></a></r>))
      element = described_class.to_binding(doc.native.root)
      expect(element).to equal(doc.native.root)
      # every bridged entry point answers on binding natives
      expect(doc.root.children.first.attributes.length).to eq(1)
      expect(doc.root.children.first["x"]).to eq("1")
    end
  end

  describe "materialize through the wrapper (issue #213)" do
    it "materializes a native-layer root without NoMethodError" do
      ctx = Moxml.new(:leptris)
      doc = ctx.parse(%(<r><a x="1">t1</a><b><c y="2">t2</c></b></r>))
      count = 0
      doc.root.materialize_fields { |*_record| count += 1 }
      expect(count).to be > 0
    end
  end

  describe "source_position (leptris 1.9.181+, upstream #1124)" do
    let(:ctx) { Moxml.new(:leptris) }

    it "answers engine source positions for parsed nodes" do
      skip "requires leptris 1.9.181" unless described_class::NATIVE_SOURCE_POSITION

      doc = ctx.parse("<root>\n  <child>text</child>\n</root>")
      expect(doc.root.source_position).to include(line: 1)
      expect(doc.root.source_position).to be_a(Hash)
    end

    it "answers nil below the gate and on other adapters" do
      expect(Moxml::Adapter::Base.source_position(nil)).to be_nil
      expect(Moxml::Adapter::Nokogiri.source_position(nil)).to be_nil
      noko = Moxml.new(:nokogiri).parse("<root><a/></root>")
      expect(noko.root.children.first.source_position).to be_nil
    end
  end

  describe "subtree digest (issue #173, leptris#869)" do
    let(:ctx) { Moxml.new(:leptris) }

    it "answers equal integers for identical subtrees parsed separately" do
      xml = %(<r xmlns:p="urn:p"><a x="1" p:y="2">t</a><b><c/></b></r>)
      d1 = ctx.parse(xml)
      d2 = ctx.parse(xml)
      expect(d1.root.digest).to be_a(Integer)
      expect(d1.root.digest).to eq(d2.root.digest)
    end

    it "answers unequal integers when content differs" do
      d1 = ctx.parse(%(<r><a x="1"/></r>))
      d2 = ctx.parse(%(<r><a x="2"/></r>))
      expect(d1.root.digest).not_to eq(d2.root.digest)
    end

    it "skips whitespace-only text with drop_ws_text" do
      spaced = ctx.parse(%(<r>\n  <a/>\n</r>))
      tight = ctx.parse(%(<r><a/></r>))
      expect(spaced.root.digest).not_to eq(tight.root.digest)
      expect(spaced.root.digest(drop_ws_text: true))
        .to eq(tight.root.digest(drop_ws_text: true))
    end

    it "hashes the prefix as well as the resolved namespace" do
      same = ctx.parse(%(<r xmlns:p="urn:p"><p:a/></r>))
      mirror = ctx.parse(%(<r xmlns:p="urn:p"><p:a/></r>))
      renamed = ctx.parse(%(<r xmlns:q="urn:p"><q:a/></r>))
      other_uri = ctx.parse(%(<r xmlns:p="urn:z"><p:a/></r>))
      base = same.root.digest
      expect(mirror.root.digest).to eq(base)
      # prefix participates (leptris#869: hash(prefix, URI, local))
      expect(renamed.root.digest).not_to eq(base)
      expect(other_uri.root.digest).not_to eq(base)
    end

    it "answers nil for nodes without a C handle" do
      doc = ctx.parse(%(<r a="1"><!-- c --><p/><?p instr?></r>))
      expect(doc.digest).to be_nil
      expect(doc.root.attributes.first.digest).to be_nil
      doc.children.select(&:declaration?).each do |decl|
        expect(decl.digest).to be_nil
      end
      # comments and PIs hash in C
      kinds = doc.root.children.map { |n| [n.is_a?(Moxml::Comment), n.is_a?(Moxml::ProcessingInstruction), n.digest] }
      comment = kinds.find { |c, _, _| c }
      pi = kinds.find { |_, p, _| p }
      expect(comment[2]).to be_a(Integer)
      expect(pi[2]).to be_a(Integer)
    end
  end
end
