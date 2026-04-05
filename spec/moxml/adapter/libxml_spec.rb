# frozen_string_literal: true

begin
  require "libxml"
rescue LoadError
  # LibXML gem not available - skip all specs in this file
  return
end

require "moxml/adapter/libxml"

RSpec.describe Moxml::Adapter::Libxml do
  around do |example|
    Moxml.with_config(:libxml, true, "UTF-8") do
      example.run
    end
  end

  it_behaves_like "xml adapter"
end
