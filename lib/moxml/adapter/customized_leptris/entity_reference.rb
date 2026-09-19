# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedLeptris
      # Parse-path face: libleptris expands the five built-in entities
      # at parse time and has no custom ones, so parsed references are
      # carried as Moxml::Entity::Reference values over marker-bearing
      # text. Programmatic creation is native (NATIVE_ENTITY_REFS,
      # binding >= 1.9.177).
      EntityReference = ::Moxml::Entity::Reference
    end
  end
end
