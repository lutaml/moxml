# frozen_string_literal: true

module Moxml
  module Adapter
    # Lifecycle record (#495): engine-gap shims for the :rexml
    # adapter. The Opal surface (this adapter's historical fallback
    # role) is deleted (moxml#489 phase 4, 2026-10-31); the shims
    # remain because the CRuby :rexml adapter calls them. The
    # adapter's fate -- the owner's removal decision, consumer
    # evidence in moxml#490 -- governs this file.
    module CustomizedRexml
      autoload :EntityReference,
               "moxml/adapter/customized_rexml/entity_reference"
      autoload :Formatter, "moxml/adapter/customized_rexml/formatter"
    end
  end
end
