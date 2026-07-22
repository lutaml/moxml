# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"
require "base64"

RSpec.describe Moxml::Signature::Algorithms::Base64Transform do
  let(:ctx) { Moxml.new(:nokogiri) }
  let(:transform) { described_class.new(context: ctx) }

  it "decodes base64 octet input" do
    encoded = Base64.strict_encode64("hello world")
    expect(transform.transform(encoded)).to eq("hello world")
  end

  it "strips whitespace before decoding" do
    encoded = Base64.strict_encode64("hello world").chars.each_slice(4).map(&:join).join("\n")
    expect(transform.transform(encoded)).to eq("hello world")
  end

  it "raises TransformError on invalid base64" do
    expect do
      transform.transform("!!!not base64!!!")
    end.to raise_error(Moxml::Signature::TransformError)
  end
end
