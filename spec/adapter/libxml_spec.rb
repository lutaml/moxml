# frozen_string_literal: true

require "libxml"
require "moxml/adapter/libxml"

RSpec.describe Moxml::Adapter::Libxml do
  around do |example|
    Moxml.with_config(:libxml, true, "UTF-8") do
      example.run
    end
  end

  it_behaves_like "xml adapter"
end
