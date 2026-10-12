# frozen_string_literal: true

require "spec_helper"

# #367: the bulk records stride carries the bound namespace URI
# for RESERVED-prefixed attributes on HTML-fragment-parsed trees —
# HTML trees carry no declarations, so the engine's attribute-URI
# face answers nil for xml:lang there; the bulk path mirrors the
# wrapper resolver's builtin table so records and wrapper agree.
RSpec.describe "materialize_fields reserved-prefix URIs (#367)" do
  let(:ctx) { Moxml.new(:leptris) }
  let(:frag) { ctx.parse_html_fragment('<span lang="en" xml:lang="en">text</span>') }
  let(:span) { frag.children.first }

  def records_attrs
    out = nil
    span.materialize_fields do |kind, _q, _p, _u, _ns, attrs, _t, _d| # rubocop:disable Metrics/ParameterLists,Lint/UnusedBlockArgument
      out = attrs.dup if kind == :element
    end
    out
  end

  it "matches the wrapper API for prefixed attributes on fragment trees" do
    records = records_attrs
    expect(records).to eq(
      ["lang", "en", nil, nil,
       "lang", "en", "http://www.w3.org/XML/1998/namespace", "xml"],
    )
  end

  it "agrees with the wrapper attribute API stride-for-stride" do
    wrapper = span.attributes.map { |a| [a.name, a.value, a.namespace&.uri, a.namespace&.prefix] }
    expect(records_attrs.each_slice(4).to_a).to eq(wrapper)
  end
end
