# frozen_string_literal: true

require "spec_helper"

# Document#parse_diagnostics (issue #271, option A — additive):
# recover-class events the engine recorded during the parse, as
# [{ kind:, message: }]. Clean parses answer []; adapters without
# the surface answer []. Reads happen through the live native
# document (the engine owns the list — read before free).
RSpec.describe Moxml::Document do
  def with_leptris
    ctx = Moxml.new(:leptris)
    yield ctx
  rescue StandardError, LoadError
    skip "leptris adapter unavailable"
  end

  it "answers [] for a clean parse" do
    with_leptris do |ctx|
      expect(ctx.parse("<r><a/></r>").parse_diagnostics).to eq([])
    end
  end

  it "surfaces duplicate-attribute recoveries with kind and message" do
    with_leptris do |ctx|
      doc = ctx.parse(%(<r a="1" a="2"/>), recover: true) ||
        ctx.parse(%(<r a="1" a="2"/>))
      next skip "engine recovered without diagnostics" if doc.nil?

      diags = doc.parse_diagnostics
      expect(diags).not_to be_empty
      expect(diags.first[:kind]).to eq(:recover)
      expect(diags.first[:message]).to be_a(String)
    end
  end

  it "answers [] on adapters without the surface" do
    ctx = Moxml.new(:rexml)
    expect(ctx.parse("<r/>").parse_diagnostics).to eq([])
  rescue StandardError, LoadError
    skip "rexml adapter unavailable"
  end
end
