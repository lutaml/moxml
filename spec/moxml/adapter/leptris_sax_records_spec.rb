# frozen_string_literal: true

require "spec_helper"

# Bulk SAX record drain (leptris#1298): on bindings carrying
# Leptris::XML::SAX::Records the leptris adapter drains the document
# in one crossing. Classic handlers must receive the SAME event
# stream the callback Recorder produces (the replay reconstructs end
# events from the records' parent indices), handlers overriding
# on_sax_records claim the raw table instead, and raw attribute
# whitespace is normalized (3.3.3) exactly where the callback path
# normalizes it.
module SaxDrainHandlers
  class EventCollector < Moxml::SAX::Handler
    attr_reader :events

    def initialize
      super
      @events = []
    end

    def on_start_document
      @events << [:start_document]
    end

    def on_end_document
      @events << [:end_document]
    end

    def on_start_element(name, attributes = {}, _namespaces = {})
      @events << [:start, name, attributes]
    end

    def on_end_element(name)
      @events << [:end, name]
    end

    def on_characters(text)
      @events << [:chars, text]
    end
  end

  class TableClaimant < Moxml::SAX::Handler
    attr_reader :tables

    def initialize
      super
      @tables = []
    end

    def on_sax_records(table)
      @tables << table
      :claimed
    end
  end
end

RSpec.describe "leptris SAX record drain", if: defined?(Leptris::XML::SAX::Records) do
  let(:context) { Moxml.new(:leptris) }
  let(:xml) do
    '<r a="x  y" xmlns="urn:default"><item n="1">t1</item>' \
      '<item n="2">t2<b>k</b></item><last/></r>'
  end

  it "replays the callback event stream through the drain" do
    drain_events = SaxDrainHandlers::EventCollector.new
    context.sax_parse(xml, drain_events)

    callback_events = SaxDrainHandlers::EventCollector.new
    bridge = Moxml::Adapter::Leptris::LeptrisSAXBridge.new(callback_events)
    Leptris::XML::SAX::Parser.new(bridge).parse(xml)

    expect(drain_events.events).to eq(callback_events.events)
    expect(drain_events.events.first).to eq([:start_document])
    expect(drain_events.events).to include([:start, "item", { "n" => "1" }])
    expect(drain_events.events).to include([:chars, "t2"])
    expect(drain_events.events.last).to eq([:end_document])
  end

  it "hands claimed tables to handlers that opt in" do
    claimant = SaxDrainHandlers::TableClaimant.new
    context.sax_parse("<r><a>n</a></r>", claimant)

    expect(claimant.tables.size).to eq(1)
    expect(claimant.tables.first.count).to eq(3)
  end
end
