# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedLeptris
      # libleptris expands the five built-in entities at parse time
      # and has no custom ones; the adapter carries entity references
      # as Moxml::Entity::Reference values over marker-bearing text.
      EntityReference = ::Moxml::Entity::Reference
    end
  end
end
