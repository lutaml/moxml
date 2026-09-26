# frozen_string_literal: true

require "spec_helper"

# Worked hot-loop adoption (moxml#279 follow-up): a builder-protocol
# driver — the shape canon's comparison lane uses — consuming the
# bulk record table directly via on_sax_records instead of the
# callback replay. The walker materializes only the strings the
# builder consumes (one name/value/text get_string each) and
# reconstructs end events from the records' parent indices, so its
# event stream is identical to the callback path while allocations
# land at the consumer-chosen floor.
#
# Docs: README "Hot-loop SAX consumption".
module RecordDriverSpec
  class Builder
    attr_accessor :events

    def initialize
      @events = []
    end

    def start_element(name, attrs)
      @events << [:start, name, attrs]
    end

    def end_element(name)
      @events << [:end, name]
    end

    def characters(text)
      @events << [:chars, text]
    end
  end

  class RecordDriver < Moxml::SAX::Handler
    def initialize(builder)
      super()
      @builder = builder
    end

    def on_sax_records(table)
      idx_stack = []
      name_stack = []
      i = 0
      count = table.count
      while i < count
        while !idx_stack.empty? && table.parent(i) != idx_stack.last
          idx_stack.pop
          @builder.end_element(name_stack.pop)
        end
        if table.kind(i).zero?
          name = table.view(i)
          attrs = []
          k = table.attr_first(i)
          last = k + table.attr_count_of(i)
          while k < last
            v = table.attr_value(k)
            attrs << [table.attr_name(k),
                      table.attr_value_has_ws?(k) ? v.tr("\t\n\r", " ") : v]
            k += 1
          end
          @builder.start_element(name, attrs)
          idx_stack << i
          name_stack << name
        else
          @builder.characters(table.view(i))
        end
        i += 1
      end
      @builder.end_element(name_stack.pop) until name_stack.empty?
      :claimed
    end
  end

  class CallbackDriver < Moxml::SAX::Handler
    attr_reader :events

    def initialize
      super
      @events = []
    end

    def on_start_element(name, attributes = {}, _namespaces = {})
      @events << [:start, name, attributes.to_a]
    end

    def on_end_element(name)
      @events << [:end, name]
    end

    def on_characters(text)
      @events << [:chars, text]
    end
  end
end

RSpec.describe "record-driven builder protocol",
               if: defined?(Leptris::XML::SAX::Records) do
  let(:context) { Moxml.new(:leptris) }
  let(:xml) do
    '<r a="x  y"><item n="1">t1</item><item n="2">t2<b>k</b></item><last/></r>'
  end

  it "feeds the builder the same stream the callback path produces" do
    record_events = RecordDriverSpec::Builder.new
    driver = RecordDriverSpec::RecordDriver.new(record_events)
    context.sax_parse(xml, driver)
    walked = record_events.events

    callback_events = RecordDriverSpec::Builder.new
    callback = RecordDriverSpec::CallbackDriver.new
    callback_events.events = []
    bridge = Moxml::Adapter::Leptris::LeptrisSAXBridge.new(callback)
    Leptris::XML::SAX::Parser.new(bridge).parse(xml)

    expect(walked).to eq(callback.events)
    expect(walked).to include([:start, "item", [["n", "1"]]])
    expect(walked).to include([:start, "r", [["a", "x  y"]]])
  end
end
