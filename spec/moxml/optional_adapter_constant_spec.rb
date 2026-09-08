# frozen_string_literal: true

require "spec_helper"

# The leptris adapter is optional: its class is required on demand by
# Moxml::Adapter.load, so under every other adapter the constant
# Moxml::Adapter::Leptris simply does not exist. Core code that branches
# on it for native fast paths must therefore gate every mention behind
# Moxml::Adapter.loaded?, or it raises
#
#   NameError: uninitialized constant Moxml::Adapter::Leptris
#
# on ordinary operations. These specs pin that down.
RSpec.describe "optional adapter constants" do
  # Exercise the code under test in the state that actually ships to
  # users who do not have leptris: the adapter class absent. Where the
  # suite runs with leptris installed, hide it for the example and put
  # it back afterwards, so the guard is proved on every machine rather
  # than only on machines missing the gem.
  def without_leptris_adapter
    mod = Moxml::Adapter
    unless mod.const_defined?(:Leptris, false) && mod.autoload?(:Leptris).nil?
      return yield
    end

    hidden = mod.const_get(:Leptris)
    mod.send(:remove_const, :Leptris)
    begin
      yield
    ensure
      mod.const_set(:Leptris, hidden)
    end
  end

  describe "Moxml::Adapter.loaded?" do
    it "is true for an adapter class that has really been loaded" do
      Moxml::Adapter.load(:ox)
      expect(Moxml::Adapter.loaded?(:ox)).to be(true)
    end

    it "answers without raising for an adapter that is not loaded" do
      expect { Moxml::Adapter.loaded?(:leptris) }.not_to raise_error
      without_leptris_adapter do
        expect(Moxml::Adapter.loaded?(:leptris)).to be(false)
      end
    end

    # Module#const_defined? reaches Object when inherit is left at its
    # default, so a bare const_defined?(:Leptris) answers "yes" for the
    # gem's own top-level ::Leptris even though Moxml::Adapter::Leptris
    # does not exist.
    it "does not mistake a same-named top-level constant for the adapter" do
      Object.const_set(:Leptrisprobe, Module.new)
      begin
        expect(Moxml::Adapter.loaded?(:leptrisprobe)).to be(false)
      ensure
        Object.send(:remove_const, :Leptrisprobe)
      end
    end

    # Both defined? and const_defined? answer "yes" for a registered but
    # unloaded autoload. Reading the constant on the strength of that
    # answer would trigger the very load the guard exists to avoid.
    it "does not report a registered-but-unloaded autoload as loaded" do
      Moxml::Adapter.autoload(:Leptrisprobe, "moxml/no/such/adapter/file")
      begin
        expect(Moxml::Adapter.loaded?(:leptrisprobe)).to be(false)
      ensure
        Moxml::Adapter.send(:remove_const, :Leptrisprobe)
      end
    end
  end

  # Deliberately excludes :leptris (the branch being guarded) and covers
  # the adapters whose namespace models differ most: native namespace
  # nodes (nokogiri, libxml), qualified names only (ox, headed_ox), and
  # the stdlib parser (rexml).
  %i[nokogiri rexml ox headed_ox libxml].each do |adapter_name|
    context "with the #{adapter_name} adapter and no leptris adapter loaded" do
      let(:doc) do
        Moxml.new(adapter_name).parse(%(<a xml:space="preserve"><b/></a>))
      end

      # Regression: AttributeResolver#resolve_value named
      # Moxml::Adapter::Leptris unguarded, so *any* prefixed attribute
      # read raised NameError unless leptris happened to be loaded.
      it "reads a prefixed attribute" do
        root = doc.root
        without_leptris_adapter do
          expect { root["xml:space"] }.not_to raise_error
          expect(root["xml:space"]).to eq("preserve")
        end
      end

      # Regression: C14n.native_inclusive10 named the same constant
      # unguarded on the default canonicalization path.
      it "canonicalizes an element" do
        root = doc.root
        without_leptris_adapter do
          expect { Moxml::C14n.canonicalize(root) }.not_to raise_error
        end
      end
    end
  end
end
