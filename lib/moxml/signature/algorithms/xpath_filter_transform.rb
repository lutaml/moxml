# frozen_string_literal: true

module Moxml
  module Signature
    module Algorithms
      # XPath Filter transform (W3C §6.6.3).
      #
      # Evaluates the XPath expression once per node in the input node-set;
      # the node is kept in the output if and only if the boolean conversion
      # of the result is true.
      #
      # The evaluation context per spec §6.6.3:
      #   - context node = the node being evaluated
      #   - context position = 1, context size = 1
      #   - in-scope namespaces from the XPath element
      #   - function library augmented with here()
      #
      # `here()` returns the node bearing the XPath expression (the XPath
      # text node's parent element, typically a ds:Transform). This is the
      # foundation of the canonical enveloped-signature pattern via XPath.
      #
      # Input: node-set. Output: node-set.
      #
      # This implementation uses moxml's XPath engine, which does not
      # currently support `here()`. The transform handles the common cases
      # (enveloped signature via `not(ancestor-or-self::dsig:Signature)`,
      # subtree selection). Full here() support is tracked in TODO 06.
      class XPathFilterTransform < TransformBase
        identifier "http://www.w3.org/TR/1999/REC-xpath-19991116"

        def self.input_type; :nodeset; end
        def self.output_type; :nodeset; end

        def transform(input)
          expression = parameters_expression
          raise TransformError, "XPath transform requires an XPath parameter" unless expression
          raise TransformError, "XPath transform requires a node-set input" unless node_set?(input)

          # Collect all descendant nodes of the input root. The XPath is
          # evaluated per-node to decide inclusion.
          all_nodes = collect_all_nodes(input_root(input))
          namespaces = xpath_namespaces
          all_nodes.select { |node| node_matches?(node, expression, namespaces) }
        end

        private

        def parameters_expression
          xpaths = @parameters.is_a?(Hash) ? @parameters[:xpaths] : nil
          return nil unless xpaths && !xpaths.empty?

          xpaths.first.to_s.strip
        end

        def xpath_namespaces
          @parameters.is_a?(Hash) ? (@parameters[:namespaces] || {}) : {}
        end

        def node_set?(input)
          input.is_a?(::Moxml::Node) || input.is_a?(Array)
        end

        def input_root(input)
          input.is_a?(Array) ? input.first : input
        end

        def collect_all_nodes(node)
          return [] unless node

          result = [node]
          if node.is_a?(::Moxml::Node)
            node.children.each do |child|
              result.concat(collect_all_nodes(child))
            end
          end
          result
        end

        # Evaluate the XPath with the node as context. moxml doesn't
        # expose a per-node context evaluation; we approximate by checking
        # the node against ancestor/descendant axes the expression mentions.
        #
        # For the canonical enveloped-signature XPath:
        #   not(ancestor-or-self::dsig:Signature)
        # we evaluate by walking ancestors.
        #
        # For general expressions, we use a heuristic: try evaluating the
        # expression as a relative path from the node. This is incomplete;
        # full XPath semantics require here() support (TODO 06).
        def node_matches?(node, expression, namespaces)
          case expression
          when /\Anot\s*\(\s*ancestor-or-self\s*::\s*(\w+):Signature\s*\)\z/
            prefix = Regexp.last_match(1)
            dsig_uri = namespaces[prefix] ||
              Moxml::Signature::DSIG_NS
            !has_ancestor_signature?(node, dsig_uri)
          when /\Anot\s*\(\s*ancestor-or-self\s*::\s*Signature\s*\)\z/
            !has_ancestor_signature?(node, Moxml::Signature::DSIG_NS)
          else
            # Generic fallback: evaluate as a relative XPath on the node.
            evaluate_generic(node, expression, namespaces)
          end
        end

        def has_ancestor_signature?(node, dsig_uri)
          current = node
          while current.is_a?(::Moxml::Element)
            return true if current.name == "Signature" &&
              current.namespace_uri == dsig_uri

            current = current.parent
          end
          false
        end

        def evaluate_generic(node, expression, namespaces)
          # Approximation: try evaluating relative to the node.
          # The moxml adapter's at_xpath returns nil if no match.
          return true unless node.is_a?(::Moxml::Element)

          result = node.at_xpath(expression, namespaces)
          !result.nil?
        rescue StandardError
          # If XPath fails, conservatively include the node.
          true
        end
      end
    end
  end
end
