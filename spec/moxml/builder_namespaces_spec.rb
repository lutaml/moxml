# frozen_string_literal: true

require "spec_helper"

# #371: Builder sharp edges — the namespace-scoped tag proxy
# (Nokogiri's xml["p"].tag parity) and the strict mode where
# unknown methods raise instead of silently becoming empty
# elements.
RSpec.describe "Builder namespaces + strict mode (#371)" do
  describe "Builder#[] namespace-scoped tags" do
    it "creates prefixed elements with text and attributes" do
      doc = Moxml.new.build do
        element("root") do
          self["w"].p("text", "a" => 1)
        end
      end
      expect(doc.root.children.first.name).to eq("w:p")
      expect(doc.to_xml).to include(%(<w:p a="1">text</w:p>))
    end

    it "nests blocks in the caller context" do
      doc = Moxml.new.build do
        element("root") do
          self["w"].sub { self["w"].deep("x") }
        end
      end
      sub = doc.root.children.first
      expect(sub.name).to eq("w:sub")
      expect(sub.children.first.name).to eq("w:deep")
      expect(sub.children.first.text).to eq("x")
    end

    it "strips the trailing-underscore escape under the prefix" do
      doc = Moxml.new.build do
        element("root") { self["epub"].type_ }
      end
      expect(doc.to_xml).to include("<epub:type>")
    end

    it "composes prefixes through nested []" do
      doc = Moxml.new.build do
        element("root") { self["w"]["ext"].node }
      end
      expect(doc.to_xml).to include("<w:ext:node>")
    end

    it "rejects a missing prefix" do
      expect { Moxml.new.build { self[nil] } }
        .to raise_error(ArgumentError, /prefix/)
    end
  end

  describe "strict mode" do
    it "raises NoMethodError for unknown methods (the silent-corruption fix)" do
      expect do
        Moxml.new.build(strict: true) do
          element("root") { build_chart_type_unused }
        end
      end.to raise_error(NoMethodError, /build_chart_type_unused/)
    end

    it "raises for unknown namespaced tags too" do
      expect do
        Moxml.new.build(strict: true) do
          element("root") { self["w"].chart_helper }
        end
      end.to raise_error(NoMethodError, /w:chart_helper/)
    end

    it "still builds known tags under strict" do
      doc = Moxml.new.build(strict: true) do
        element("root") { text "ok" }
      end
      expect(doc.to_xml).to include("<root>ok</root>")
    end

    it "defaults off and honors config.builder_strict" do
      expect(Moxml.new.config.builder_strict).to be(false)
      ctx = Moxml.new
      ctx.config.builder_strict = true
      expect do
        ctx.build { element("root") { helperish } }
      end.to raise_error(NoMethodError)
    end

    it "a per-build false overrides a strict config" do
      ctx = Moxml.new
      ctx.config.builder_strict = true
      doc = ctx.build(strict: false) do
        element("root") { helperish }
      end
      expect(doc.to_xml).to include("<helperish>")
    end
  end
end
