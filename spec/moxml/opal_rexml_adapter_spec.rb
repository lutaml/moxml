# frozen_string_literal: true

require "spec_helper"
require "moxml/adapter/shared_examples/adapter_contract"

RSpec.describe Moxml::Adapter::Rexml, if: RUBY_ENGINE == "opal" do
  around do |example|
    Moxml.with_config(:rexml, true, "UTF-8") do
      example.run
    end
  end

  it_behaves_like "xml adapter"
end
