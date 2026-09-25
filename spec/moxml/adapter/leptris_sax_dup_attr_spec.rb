# frozen_string_literal: true

require "spec_helper"

# Duplicate attributes are a fatal XML 1.0 §3.1 error (moxml#281,
# issue #130 banner semantics): the SAX lane must surface them via
# on_error exactly like the DOM lane's parse_diagnostics. On
# bindings whose drain claims dup-containing documents (engine <
# 1.9.242 — leptris#1374), the drain swallows the error; those
# bindings skip this spec until the ride lands.
RSpec.describe "SAX duplicate-attribute error surfacing" do
  let(:context) { Moxml.new(:leptris) }
  let(:dup_xml) do
    '<body lang="en" xml:lang="en" xml:lang="en"><div>x</div></body>'
  end

  class ErrorCollector < Moxml::SAX::Handler
    attr_reader :errors, :elements

    def initialize
      super
      @errors = []
      @elements = 0
    end

    def on_error(error)
      @errors << error.message
    end

    def on_start_element(name, _attrs = {}, _namespaces = {})
      @elements += 1
    end
  end

  it "surfaces the redefined-attribute error through sax_parse" do
    if defined?(Leptris::XML::SAX::Records) &&
       !Leptris::XML::SAX::Records.open(dup_xml).nil?
      skip "engine < 1.9.242 — the drain claims dup-attr documents " \
           "(leptris#1374)"
    end

    handler = ErrorCollector.new
    context.sax_parse(dup_xml, handler)

    expect(handler.errors.join).to include("xml:lang redefined")
    expect(handler.elements).to eq(2)
  end
end
