# frozen_string_literal: true

# Parse-path alias: rexml expands the built-in entities at parse time,
# so parsed references are the facade's Moxml::Entity::Reference values.
# Lifecycle: the :rexml adapter's fate governs this file; the
# adapter's historical Opal role ended with #489 phase 4. Third-party
# engine, no upstream ask.

module Moxml
  module Adapter
    module CustomizedRexml
      EntityReference = ::Moxml::Entity::Reference
    end
  end
end
