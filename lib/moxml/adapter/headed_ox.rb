# frozen_string_literal: true

require_relative "ox"
require_relative "../xpath"
# Force load XPath modules (autoload doesn't work well with relative requires in examples)
require_relative "../xpath/parser"
require_relative "../xpath/compiler"

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
        # Override parse to use lazy wrapping like the Ox adapter.
        # Previously used DocumentBuilder (eager tree construction causing
        # ~176K allocations per 100-element parse). Lazy parse defers wrapper
        # creation until nodes are accessed, matching Ox adapter behavior.
        def parse(xml, options = {}, _context = nil)
          processed_xml = preprocess_entities(xml)
          native_doc = begin
            result = ::Ox.parse(processed_xml)

            # result can be either Document or Element
            if result.is_a?(::Ox::Document)
              assign_parents(result)
              validate_single_root(result) if options[:strict]
              result
            else
              doc = ::Ox::Document.new
              doc << result
              assign_parents(doc)
              doc
            end
          rescue ::Ox::ParseError => e
            raise Moxml::ParseError.new(
              e.message,
              source: xml.is_a?(String) ? xml[0..100] : nil,
            )
          end

          # Use provided context if available, otherwise create new one
          ctx = _context || Context.new(:headed_ox)
          Document.new(native_doc, ctx)
        end

        # Execute XPath query using Moxml's XPath engine
        #
        # This overrides the Ox adapter's xpath method which uses locate().
        #
        # @param node Starting node (native or wrapped)
        # @param [String] expression XPath expression
        # @param [Hash] namespaces Namespace prefix mappings
        # @return [Array, Object] Native node array or scalar value
        def xpath(node, expression, namespaces = {})
          # If we receive a native node, wrap it first
          # Document#xpath passes @native, but our compiled XPath needs Moxml nodes
          unless node.is_a?(Moxml::Node)
            # Determine the context from the node if possible
            # For now, create a basic context for wrapped nodes
            ctx = Context.new(:headed_ox)

            # Wrap the native node - don't rebuild the whole document
            node = Moxml::Node.wrap(node, ctx)
          end

          # Parse XPath expression to AST
          ast = XPath::Parser.parse(expression)

          # Compile AST to executable Proc using class method
          proc = XPath::Compiler.compile_with_cache(ast, namespaces: namespaces)

          # Execute on the node (now guaranteed to be wrapped Moxml node)
          result = proc.call(node)

          # Return native arrays for Node#xpath to wrap, scalars directly.
          # The adapter contract: xpath() returns Array<native> | scalar.
          case result
          when Array
            # XPath engine returns wrapped Moxml::Node objects.
            # Extract native nodes and deduplicate by object identity.
            native_nodes = result.map { |n| n.is_a?(Moxml::Node) ? n.native : n }
            seen = {}
            native_nodes.select do |native|
              id = native.object_id
              if seen[id]
                false
              else
                seen[id] = true
              end
            end
          when NodeSet
            # NodeSet from intermediate evaluation - extract natives and deduplicate
            seen = {}
            result.to_a.map(&:native).select do |native|
              id = native.object_id
              if seen[id]
                false
              else
                seen[id] = true
              end
            end
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
        # @return [Object, nil] First native node or scalar value
        def at_xpath(node, expression, namespaces = {})
          result = xpath(node, expression, namespaces)
          result.is_a?(Array) ? result.first : result
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
