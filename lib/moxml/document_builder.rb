# frozen_string_literal: true

module Moxml
  # Deprecated compatibility facade retained for 0.2-era callers.
  #
  # DocumentBuilder was the parse entry point before 0.3.0 retired it
  # in favor of Context#parse; deleting the constant broke downstream
  # gems that referenced it directly (issue #124). It now delegates to
  # Context#parse, so `build(xml_string)` returns a parsed document —
  # unlike the 0.2-era behavior of silently returning an empty one.
  class DocumentBuilder
    attr_reader :context

    def initialize(context)
      @context = context
    end

    def build(xml)
      context.parse(xml)
    end
  end
end
