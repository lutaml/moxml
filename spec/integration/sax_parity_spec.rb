# frozen_string_literal: true

# SAX event parity across adapters: every bridge must translate its
# native SAX stream into the same Moxml event sequence — same element
# names (qualified), same attribute/declaration split (nil key = the
# default namespace), same characters.
RSpec.describe "SAX parity across adapters" do
  let(:xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root xmlns="http://d.org" xmlns:p="http://p.org" kind="a"><p:child id="1">text</p:child></root>
    XML
  end

  def recorded_events(adapter_name)
    events = []
    handler = Class.new(Moxml::SAX::Handler) do
      define_method(:track) { |*event| events << event }
      define_method(:on_start_document) { track(:start_document) }
      define_method(:on_end_document) { track(:end_document) }
      define_method(:on_start_element) { |n, a, ns| track(:start_element, n, a, ns) }
      define_method(:on_end_element) { |n| track(:end_element, n) }
      define_method(:on_characters) { |t| track(:characters, t) }
    end
    Moxml.new(adapter_name).sax_parse(xml, handler.new)
    events
  end

  def assert_parity(adapter_name)
    # REXML and Oga report document-level whitespace (between the
    # declaration and the root) as characters; parity is over the
    # meaningful event stream.
    events = recorded_events(adapter_name)
      .reject { |event| event[0] == :characters && event[1].to_s.strip.empty? }

    expect(events.first).to eq([:start_document])
    expect(events[1]).to eq(
      [:start_element, "root",
       { "kind" => "a" },
       { nil => "http://d.org", "p" => "http://p.org" }],
    )
    expect(events[2]).to eq([:start_element, "p:child", { "id" => "1" }, {}])
    expect(events).to include([:characters, "text"])
    expect(events).to include([:end_element, "p:child"])
    expect(events).to include([:end_element, "root"])
    expect(events.last).to eq([:end_document])
  end

  adapters = %i[nokogiri oga rexml ox headed_ox libxml]
  adapters << :leptris if Object.const_defined?(:Leptris) &&
    Leptris::XML::Document.respond_to?(:create)

  adapters.each do |adapter_name|
    it "emits the same event stream via #{adapter_name}" do
      assert_parity(adapter_name)
    end
  end
end
