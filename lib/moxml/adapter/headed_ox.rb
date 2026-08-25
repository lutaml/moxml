# frozen_string_literal: true

return if RUBY_ENGINE == "opal"

require "moxml/adapter/ox"

module Moxml
  module Adapter
    # HeadedOx adapter - Ox parsing with Moxml's XPath engine.
    #
    # Since the Ox adapter now routes XPath through Moxml's pure-Ruby
    # XPath 1.0 engine, HeadedOx is the historical name for exactly
    # that combination and inherits everything from Adapter::Ox. It
    # exists for backwards compatibility and reports its own
    # capabilities.
    #
    # @example
    #   context = Moxml.new(:headed_ox)
    #   doc = context.parse(xml_string)
    #   results = doc.xpath('//book[@price < 10]/title')
    #
    class HeadedOx < Ox
      class << self
        def context_adapter_name
          :headed_ox
        end

        # Report adapter capabilities
        #
        # @return [Hash] Capability flags
        def capabilities
          {
            parse: true,
            sax_parsing: true,
            namespace_aware: true,
            namespace_support: :partial,
            dtd_support: true,
            parsing_speed: :fast,

            # XPath via Moxml's XPath engine
            xpath_support: :full,
            xpath_full: true,
            xpath_axes: :partial, # 6 of 13 axes: child, descendant, descendant-or-self, self, attribute, parent
            xpath_functions: :complete, # All 27 XPath 1.0 functions
            xpath_predicates: true,
            xpath_namespaces: true,
            xpath_variables: true,

            namespace_serialization: true,
            pretty_print: true,

            schema_validation: false,
            xslt_support: false,
          }
        end
      end
    end
  end
end
