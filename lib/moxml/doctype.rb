# frozen_string_literal: true

module Moxml
  # Represents an XML DOCTYPE declaration
  #
  # @note Doctype accessor methods are not fully implemented across all adapters.
  #   The availability of #name, #external_id, and #system_id depends on whether
  #   the specific adapter implements the corresponding adapter methods:
  #   - adapter.doctype_name(native)
  #   - adapter.doctype_external_id(native)
  #   - adapter.doctype_system_id(native)
  #
  #   Most adapters do not currently implement these methods. If you need DOCTYPE
  #   information, consider using adapter-specific methods or parsing the serialized
  #   XML manually.
  class Doctype < Node
    # Returns the DOCTYPE name (root element name)
    #
    # @return [String, nil] the DOCTYPE name
    # @raise [NotImplementedError] if the adapter doesn't implement doctype_name
    def name
      adapter.doctype_name(@native)
    end

    # Returns the DOCTYPE external ID
    #
    # @return [String, nil] the external ID
    # @raise [NotImplementedError] if the adapter doesn't implement doctype_external_id
    def external_id
      adapter.doctype_external_id(@native)
    end

    # Returns the DOCTYPE system ID
    #
    # @return [String, nil] the system ID
    # @raise [NotImplementedError] if the adapter doesn't implement doctype_system_id
    def system_id
      adapter.doctype_system_id(@native)
    end

    # Returns the primary identifier for this doctype
    # Since DOCTYPE information is not reliably available across adapters,
    # this returns nil.
    #
    # @return [nil]
    def identifier
      name
    end
  end
end
