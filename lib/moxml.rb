# lib/moxml.rb
module Moxml
  class << self
    def new(adapter = nil, &block)
      context = Context.new(adapter)
      context.config.instance_eval(&block) if block_given?
      context
    end

    def configure
      yield Config.default if block_given?
    end
  end
end

require_relative "moxml/version"
require_relative "moxml/document"
require_relative "moxml/document_builder"
require_relative "moxml/error"
require_relative "moxml/node_factory"
require_relative "moxml/builder"
require_relative "moxml/config"
require_relative "moxml/context"
require_relative "moxml/adapter"
