# frozen_string_literal: true

require "spec_helper"

# leptris#1866: a cross-document replace used to hand back the
# SCRATCH document's wrapper — the adapter's insert deep-copies the
# subtree into the target, so the returned wrapper's native pointer
# belonged to the scratch arena. Callers stored it (svg cleanup
# keeps `new_svg` for id bookkeeping), the scratch was collected,
# and every later read of the stored wrapper walked freed memory:
# serializer segfaults and `<use ="">` empty-attribute names in
# the output.
RSpec.describe "leptris cross-document replace survival" do
  let(:context) { Moxml.new(:leptris) }

  it "keeps the installed wrapper valid after the scratch is collected" do
    host = context.parse(
      '<root xmlns:xlink="http://www.w3.org/1999/xlink">' \
      '<svg xmlns="http://www.w3.org/2000/svg" id="s1">' \
      '<use xlink:href="#a"/><use href="#b"/></svg></root>',
    )
    scratch = context.parse(
      "<svg xmlns=\"http://www.w3.org/2000/svg\" id=\"fresh\">" \
      "<use xlink:href=\"#fx\"/><use href=\"#b\"/></svg>",
    )
    olds = host.root.children.select { |c| c.name == "svg" }
    olds[0].replace(scratch.root)
    GC.start(full_mark: true, immediate_sweep: true)
    out = host.root.to_xml
    expect(out).not_to include("<use =")
    # the installed copy's OWN content survives the scratch GC
    expect(out).to include("fx").and include("#b")
    # NOTE: pre-existing divergence D-22 (materialized-wrapper
    # lane) — the UNREPLACED siblings of a cross-doc replace are
    # dropped; reproduced on the stock adapter before this fix.
  end
end
