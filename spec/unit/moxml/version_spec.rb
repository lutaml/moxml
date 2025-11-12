# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Moxml::VERSION" do
  it "has a version number" do
    expect(Moxml::VERSION).not_to be_nil
    expect(Moxml::VERSION).to be_a(String)
  end

  it "follows semantic versioning" do
    expect(Moxml::VERSION).to match(/\d+\.\d+\.\d+/)
  end
end
