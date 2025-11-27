# frozen_string_literal: true

# Load adapter first - it sets up PATH for DLLs on Windows before requiring libxml
require "moxml/adapter/libxml"

RSpec.describe Moxml::Adapter::Libxml do
  around do |example|
    Moxml.with_config(:libxml, true, "UTF-8") do
      example.run
    end
  end

  it_behaves_like "xml adapter"
end
