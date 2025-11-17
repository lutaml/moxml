# frozen_string_literal: true

module Moxml
  class Doctype < Node
    def name
      adapter.doctype_name(@native)
    end

    def external_id
      adapter.doctype_external_id(@native)
    end

    def system_id
      adapter.doctype_system_id(@native)
    end
  end
end
