# frozen_string_literal: true

# Parse-path alias: ox expands the built-in entities at parse time and
# has no reference nodes, so parsed references are the facade's
# Moxml::Entity::Reference values. Lifecycle: the :ox adapter is
# deprecated (#491) — this record dies with it.

module Moxml
  module Adapter
    module CustomizedOx
      EntityReference = ::Moxml::Entity::Reference
    end
  end
end
