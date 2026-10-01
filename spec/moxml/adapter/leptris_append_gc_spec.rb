# frozen_string_literal: true

require "spec_helper"

# moxml#304: cross-document append_xml / add_child silently lost
# appended subtrees under GC pressure on MRI < 3.4 — the wrapper
# registry's WeakMap loses/mangles entries during incremental GC
# marking (moxml#303's root cause) while the appended fragment's
# natives are only weakly held; the references then read freed
# natives ("<sections></sections>", nameless element pairs).
# The strong-registry fallback (WEAK_WRAPPERS=false on MRI < 3.4)
# resolves it; this pins the shape.
RSpec.describe "leptris cross-document append under GC pressure" do
  let(:ctx) { Moxml.new(:leptris) }
  let(:frags) do
    [
      '<clause id="a"><p>one</p></clause>',
      '<annex id="b"><p>two &amp; more</p><fn ref="1"/><!-- c --></annex>',
      '<p standalone="x" y="1"/>',
    ]
  end

  it "keeps appended subtrees across collections" do
    8.times do
      root = ctx.parse("<sections/>").root
      frags.each do |frag|
        root.append_xml(frag)
        GC.start(full_mark: true, immediate_sweep: true)
      end
      out = root.to_xml(indent: 0)
      expect(out).to include("<clause")
      expect(out).to include("<annex")
      expect(out).to include("standalone")
      expect(out).not_to include("<></>")
    end
  end

  it "keeps parse_fragment nodes across collections" do
    built = ctx.parse("<sections/>")
    4.times do
      frags.each do |frag|
        ctx.parse_fragment(frag).each do |node|
          built.root.add_child(node)
          GC.start(full_mark: true, immediate_sweep: true)
        end
      end
      out = built.root.to_xml(indent: 0)
      expect(out).to include("<clause")
      expect(out).to include("<annex")
    end
  end

  # moxml#308: the pin list must dedup by identity — one source
  # document's children attach node-by-node, and without dedup the
  # list grows linearly with append count (GB-scale malloc on
  # large-document hydration; OOM at 43-75M slots).
  it "pins each adopted document once regardless of append count" do
    target = ctx.parse("<r/>")
    frag = ctx.parse("<m>#{Array.new(300) { |i| "<c#{i}>x</c#{i}>" }.join}</m>")
    frag.root.children.each { |c| target.root.add_child(c) }

    docs = ctx.config.adapter.attachments.get(target.native.document, :adopted_docs)
    expect(docs.size).to eq(1)
    expect(target.root.to_xml).to include("<c299")
  end
end
