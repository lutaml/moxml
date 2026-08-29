# frozen_string_literal: true

require "nokogiri"
require "moxml/adapter/nokogiri"

RSpec.describe Moxml::Adapter::Nokogiri do
  around do |example|
    Moxml.with_config(:nokogiri, true, "UTF-8") do
      example.run
    end
  end

  it_behaves_like "xml adapter"

  describe "recover-mode error channel" do
    it "exposes recoverable syntax errors as parse_errors" do
      doc = Moxml.new(:nokogiri).parse("<root><unclosed>", strict: false)
      expect(doc.parse_errors).not_to be_empty
      expect(doc.parse_errors).to all(be_a(String))
    end
  end
end
