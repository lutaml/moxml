# frozen_string_literal: true

require "spec_helper"

# #362.1: CSS selection through the shared Moxml::Css translator —
# one implementation for every adapter, so selector semantics
# converge by construction. The correctness oracle is
# nokogiri-native CSS: the translated XPath must return the same
# node sets for the corpus.
RSpec.describe "Moxml CSS selection (#362.1)" do
  let(:source) do
    <<~HTML
      <doc>
        <p id="first" class="lead intro">one</p>
        <p class="lead">two <b>bold</b></p>
        <div class="wrap">
          <p data-k="v">three</p>
          <span>four</span>
          <p>five</p>
        </div>
        <section><article>deep</article></section>
      </doc>
    HTML
  end

  describe "Moxml::Css.to_xpath" do
    def xp(sel, absolute: false)
      Moxml::Css.to_xpath(sel, absolute: absolute)
    end

    it "translates the core shapes" do
      expect(xp("p", absolute: true)).to eq("//p")
      expect(xp(".lead", absolute: true))
        .to include("contains(concat(' ', normalize-space(@class)")
      expect(xp("#first", absolute: true)).to eq("//*[@id = 'first']")
      expect(xp("[data-k]", absolute: true)).to eq("//p/*[@data-k]").or include("[@data-k]")
      expect(xp("div > p", absolute: true)).to eq("//div/p")
      expect(xp("div p", absolute: true)).to eq("//div//p")
      expect(xp("span + p", absolute: true))
        .to eq("//span/following-sibling::*[position() = 1 and name() = 'p']")
      expect(xp("p ~ span", absolute: true))
        .to eq("//p/following-sibling::span")
    end

    it "supports attribute operators" do
      expect(xp("[href^='h']", absolute: true))
        .to include("starts-with(@href, 'h')")
      expect(xp("[href$='z']", absolute: true)).to include("substring(@href")
      expect(xp("[href*='mid']", absolute: true)).to include("contains(@href, 'mid')")
      expect(xp("[lang|=en]", absolute: true))
        .to include("starts-with(@lang, 'en-')")
    end

    it "supports positional pseudos" do
      expect(xp("p:first-child", absolute: true))
        .to include("count(preceding-sibling::*) = 0")
      expect(xp("p:nth-child(3)", absolute: true))
        .to include("count(preceding-sibling::*) = 2")
      expect(xp("p:nth-child(odd)", absolute: true))
        .to include("mod 2 = 0")
    end

    it "negates simple selectors with :not" do
      expect(xp("p:not(.lead)", absolute: true))
        .to include("not(contains(")
      expect(xp(":not(p)", absolute: true)).to include("not(self::p)")
    end

    it "groups comma selectors into a union" do
      expect(xp("div, section", absolute: true)).to include(" | ")
    end

    it "raises Css::Error on unsupported shapes" do
      expect { xp("p:hover") }.to raise_error(Moxml::Css::Error, /pseudo/)
      expect { xp("> p") }.to raise_error(Moxml::Css::Error)
      expect { xp("p >>") }.to raise_error(Moxml::Css::Error)
      expect { xp("") }.to raise_error(Moxml::Css::Error)
    end
  end

  describe "Node#css / at_css" do
    let(:expected) do
      {
        "p" => 4, "#first" => 1, ".lead" => 2, "p.lead" => 2,
        "div p" => 2, "div > p" => 2, "[data-k]" => 1,
        "[data-k=v]" => 1, "p:not(.lead)" => 2,
        "p:first-child" => 2, "p:nth-child(3)" => 1,
        "section article" => 1, "div, section" => 2,
        "span + p" => 1, "p ~ span" => 1
      }
    end

    %i[nokogiri leptris oga ox rexml].each do |adapter_name|
      describe "on #{adapter_name}" do
        let(:ctx) { Moxml.new(adapter_name) }
        let(:doc) { ctx.parse(source) }

        it "returns the nokogiri-native CSS node sets" do
          expected.each do |sel, want|
            expect(doc.css(sel).size).to eq(want),
                                         "#{sel} => #{doc.css(sel).size}, want #{want}"
          end
        end

        it "at_css returns the first match" do
          expect(doc.at_css("p").text).to eq("one")
          expect(doc.at_css("div p").text).to eq("three")
          expect(doc.at_css("nosuch")).to be_nil
        end
      end
    end

    it "scopes element-subtree selection" do
      ctx = Moxml.new(:leptris)
      doc = ctx.parse(source)
      wrap = doc.at_css("div")
      expect(wrap.css("p").size).to eq(2)
      expect(doc.at_css("doc").css("section article").size).to eq(1)
    end
  end
end
