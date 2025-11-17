# frozen_string_literal: true

require_relative "ox"

module Moxml
  module Adapter
    # HeadedOx adapter - combines Ox's fast parsing with Moxml's XPath engine.
    #
    # This adapter uses:
    # - Ox for XML parsing (fast C-based parser)
    # - Moxml::XPath engine for comprehensive XPath 1.0 support
    #
    # Unlike the standard Ox adapter which has limited XPath support through
    # Ox's locate() method, HeadedOx provides full XPath 1.0 functionality
    # including all axes, predicates, and 27 standard functions.
    #
    # @example
    #   context = Moxml.new(:headed_ox)
    #   doc = context.parse(xml_string)
    #   results = doc.xpath('//book[@price < 10]/title')
    #
    class HeadedOx < Ox
      class << self
        # Override parse to use HeadedOx context instead of Ox context
        def parse(xml, _options = {})
          native_doc = begin
            result = ::Ox.parse(xml)

            # result can be either Document or Element
            if result.is_a?(::Ox::Document)
              result
            else
              doc = ::Ox::Document.new
              doc << result
              doc
            end
          rescue ::Ox::ParseError => e
            raise Moxml::ParseError.new(
              e.message,
              source: xml.is_a?(String) ? xml[0..100] : nil,
            )
          end

          # Use :headed_ox context instead of :ox
          DocumentBuilder.new(Context.new(:headed_ox)).build(native_doc)
        end

        # Execute XPath query using Moxml's XPath engine
        #
        # This overrides the Ox adapter's xpath method which uses locate().
        #
        # @param [Moxml::Node] node Starting node (wrapped Moxml node)
        # @param [String] expression XPath expression
        # @param [Hash] namespaces Namespace prefix mappings
        # @return [Moxml::NodeSet, Object] Query results
        def xpath(node, expression, namespaces = {})
          # If we receive a native node, wrap it first
          # Document#xpath passes @native, but our compiled XPath needs Moxml nodes
          unless node.is_a?(Moxml::Node)
            # Determine the context from the node if possible
            # For now, create a basic context for wrapped nodes
            ctx = Context.new(:headed_ox)

            # Wrap the native node - don't rebuild the whole document
            node = Node.wrap(node, ctx)
          end

          # Parse XPath expression to AST
          ast = XPath::Parser.parse(expression)

          # Compile AST to executable Proc using class method
          proc = XPath::Compiler.compile_with_cache(ast, namespaces: namespaces)

          # Execute on the node (now guaranteed to be wrapped Moxml node)
          result = proc.call(node)

          # Wrap Array results in NodeSet, return other types directly
          case result
          when Array
            # Deduplicate by native object identity to handle descendant-or-self
            # which may yield the same native node multiple times
            nodeset = NodeSet.new(result, node.context)
            nodeset.uniq_by_native
          when NodeSet
            # Deduplicate NodeSet results as well
            result.uniq_by_native
          else
            # Scalar values (string, number, boolean) - return as-is
            result
          end
        rescue StandardError => e
          raise Moxml::XPathError.new(
            "XPath execution failed: #{e.message}",
            expression: expression,
            adapter: "HeadedOx",
            node: node,
          )
        end

        # Execute XPath query and return first result
        #
        # @param [Moxml::Node] node Starting node
        # @param [String] expression XPath expression
        # @param [Hash] namespaces Namespace prefix mappings
        # @return [Moxml::Node, Object, nil] First result or nil
        def at_xpath(node, expression, namespaces = {})
          result = xpath(node, expression, namespaces)
          result.is_a?(NodeSet) ? result.first : result
        end

        # Check if XPath is supported
        #
        # @return [Boolean] Always true for HeadedOx
        def xpath_supported?
          true
        end

        # Report adapter capabilities
        #
        # HeadedOx extends Ox's capabilities with full XPath support
        # through Moxml's XPath engine
        #
        # @return [Hash] Capability flags
        def capabilities
          {
            # Core adapter capabilities
            parse: true,

            # Parsing capabilities (inherited from Ox)
            sax_parsing: true,
            namespace_aware: true,
            namespace_support: :partial,
            dtd_support: true,
            parsing_speed: :fast,

            # XPath capabilities (provided by Moxml's XPath engine)
            xpath_support: :full,
            xpath_full: true,
            xpath_axes: :partial, # 6 of 13 axes: child, descendant, descendant-or-self, self, attribute, parent
            xpath_functions: :complete, # All 27 XPath 1.0 functions
            xpath_predicates: true,
            xpath_namespaces: true,
            xpath_variables: true,

            # Serialization capabilities (inherited from Ox)
            namespace_serialization: true,
            pretty_print: true,

            # Known limitations
            schema_validation: false,
            xslt_support: false,
          }
        end
      end
    end
  end
end
