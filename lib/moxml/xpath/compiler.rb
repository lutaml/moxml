# frozen_string_literal: true

module Moxml
  module XPath
    # Compiler for transforming XPath AST into executable Ruby code.
    #
    # This class takes an XPath AST (produced by Parser) and compiles it into
    # a Ruby Proc that can be executed against XML documents. The compilation
    # process:
    #
    # 1. Traverse the XPath AST
    # 2. Generate Ruby::Node AST representing Ruby code
    # 3. Use Ruby::Generator to convert to Ruby source string
    # 4. Evaluate source in Context to get a Proc
    #
    # @example
    #   ast = Parser.parse("//book")
    #   proc = Compiler.compile_with_cache(ast)
    #   result = proc.call(document)
    #
    # @private
    class Compiler
      # Shared context for compiled Procs
      CONTEXT = Context.new

      # Expression cache
      CACHE = Cache.new

      # Wildcard for node names/namespace prefixes
      STAR = "*"

      # Node types that require a NodeSet to push nodes into
      RETURN_NODESET = %i[path absolute_path relative_path axis
                          predicate].freeze

      # Compiles and caches an AST
      #
      # @param ast [AST::Node] XPath AST to compile
      # @param namespaces [Hash, nil] Optional namespace prefix mappings
      # @return [Proc] Compiled Proc that accepts a document
      def self.compile_with_cache(ast, namespaces: nil)
        cache_key = namespaces ? [ast, namespaces] : ast
        CACHE.get_or_set(cache_key) { new(namespaces: namespaces).compile(ast) }
      end

      # Initialize compiler
      #
      # @param namespaces [Hash, nil] Optional namespace prefix mappings
      def initialize(namespaces: nil)
        @namespaces = namespaces
        @literal_id = 0
        @predicate_nodesets = []
        @predicate_indexes = []
      end

      # Compiles an XPath AST into a Ruby Proc
      #
      # @param ast [AST::Node] XPath AST to compile
      # @return [Proc] Executable Proc
      def compile(ast)
        document = literal(:node)
        matched = matched_literal
        context_var = context_literal

        ruby_ast = if return_nodeset?(ast)
                     process(ast, document) { |node| matched.push(node) }
                   else
                     process(ast, document)
                   end

        proc_ast = literal(:lambda).add_block(document) do
          # Get context from document
          context_assign = context_var.assign(document.context)

          if return_nodeset?(ast)
            # Create NodeSet using send node: Moxml::NodeSet.new([], context)
            nodeset_class = const_ref("Moxml", "NodeSet")
            empty_array = Ruby::Node.new(:array, [])
            nodeset_new = Ruby::Node.new(:send,
                                         [nodeset_class, "new", empty_array,
                                          context_var])

            body = matched.assign(nodeset_new)
              .followed_by(ruby_ast)
              .followed_by(matched)
          else
            body = ruby_ast
          end

          context_assign.followed_by(body)
        end

        generator = Ruby::Generator.new
        source = generator.process(proc_ast)

        CONTEXT.evaluate(source)
      ensure
        @literal_id = 0
        @predicate_nodesets.clear
        @predicate_indexes.clear
      end

      # Process a single XPath AST node
      #
      # @param ast [AST::Node] AST node to process
      # @param input [Ruby::Node] Input node
      # @yield [Ruby::Node] Yields matched nodes if block given
      # @return [Ruby::Node] Ruby AST node
      def process(ast, input, &block)
        send(:"on_#{ast.type}", ast, input, &block)
      end

      private

      # Helper methods for creating Ruby AST nodes

      def literal(value)
        case value
        when Symbol, String
        end
        Ruby::Node.new(:lit, [value.to_s])
      end

      # Create a constant reference like Moxml::Document
      def const_ref(*parts)
        Ruby::Node.new(:const, parts)
      end

      def unique_literal(name)
        @literal_id += 1
        literal("#{name}#{@literal_id}")
      end

      def string(value)
        Ruby::Node.new(:string, [value.to_s])
      end

      def symbol(value)
        Ruby::Node.new(:symbol, [value.to_sym])
      end

      def matched_literal
        literal(:matched)
      end

      def context_literal
        literal(:context)
      end

      def self_nil
        @self_nil ||= literal(:nil)
      end

      def self_true
        @self_true ||= literal(true)
      end

      def self_false
        @self_false ||= literal(false)
      end

      def return_nodeset?(ast)
        RETURN_NODESET.include?(ast.type)
      end

      # Type checking helpers

      def document_or_node(node)
        doc_class = const_ref("Moxml", "Document")
        node_class = const_ref("Moxml", "Node")
        node.is_a?(doc_class).or(node.is_a?(node_class))
      end

      def element_or_attribute(node)
        elem_class = const_ref("Moxml", "Element")
        attr_class = const_ref("Moxml", "Attribute")
        node.is_a?(elem_class).or(node.is_a?(attr_class))
      end

      def attribute_or_node(node)
        attr_class = const_ref("Moxml", "Attribute")
        node_class = const_ref("Moxml", "Node")
        node.is_a?(attr_class).or(node.is_a?(node_class))
      end

      # Path handling

      # Handle absolute paths like /root or //descendant
      def on_absolute_path(ast, input, &block)
        if ast.children.empty?
          # Just "/" - return the document/root
          yield input if block_given?
          input
        else
          # Process steps from the input (which should be a document)
          # Don't call input.root - that would skip a level
          first_child = ast.children[0]

          # For absolute paths, we process from the document itself
          if ast.children.size == 1
            process(first_child, input, &block)
          else
            # Multiple steps - create a path
            path_node = AST::Node.new(:path, ast.children)
            process(path_node, input, &block)
          end
        end
      end

      # Handle relative paths
      def on_relative_path(ast, input, &block)
        on_path(ast, input, &block)
      end

      # Handle path (series of steps)
      def on_path(ast, input, &block)
        return input if ast.children.empty?

        # First step from input
        first_step = ast.children[0]

        if ast.children.size == 1
          # Single step
          process(first_step, input, &block)
        else
          # Multiple steps - need to accumulate results
          temp_results = unique_literal(:temp_results)
          context_var = context_literal

          # Create NodeSet for temp results
          nodeset_class = const_ref("Moxml", "NodeSet")
          empty_array = Ruby::Node.new(:array, [])
          nodeset_new = Ruby::Node.new(:send,
                                       [nodeset_class, "new", empty_array,
                                        context_var])

          temp_results.assign(nodeset_new)
            .followed_by do
              process(first_step, input) do |node|
                temp_results.push(node)
              end
                .followed_by do
                # Process remaining steps on each result
                remaining_steps = AST::Node.new(:path, ast.children[1..])
                temp_node = unique_literal(:temp_node)

                temp_results.each.add_block(temp_node) do
                  process(remaining_steps, temp_node, &block)
                end
              end
            end
        end
      end

      # Axis handling

      # Dispatch axes to specific handlers
      def on_axis(ast, input)
        axis_name, test, *predicates = ast.children

        handler = axis_name.gsub("-", "_")

        send(:"on_axis_#{handler}", test, input) do |matched|
          if predicates.empty?
          else
            # Will implement predicate handling later
          end
          yield matched
        end
      end

      # AXIS: child - direct children
      def on_axis_child(ast, input)
        child = unique_literal(:child)

        document_or_node(input).if_true do
          input.children.each.add_block(child) do
            process(ast, child).if_true { yield child }
          end
        end
      end

      # AXIS: self - the node itself
      def on_axis_self(ast, input)
        process(ast, input).if_true { yield input }
      end

      # AXIS: parent - parent node
      def on_axis_parent(ast, input)
        parent = unique_literal(:parent)

        attribute_or_node(input).if_true do
          parent.assign(input.parent).followed_by do
            process(ast, parent).if_true { yield parent }
          end
        end
      end

      # Node test handling

      # Handle node tests (name matching)
      def on_test(ast, input)
        condition = element_or_attribute(input)
        name_match = match_name_and_namespace(ast, input)

        name_match ? condition.and(name_match) : condition
      end

      # Handle wildcard test (*)
      def on_wildcard(_ast, input)
        element_or_attribute(input)
      end

      # Match element/attribute names and namespaces
      def match_name_and_namespace(ast, input)
        ns = ast.value[:namespace]
        name = ast.value[:name]

        condition = nil
        name_str = string(name)
        zero = literal(0)

        # Match name (case-insensitive)
        if name != STAR
          condition = input.name.eq(name_str)
            .or(input.name.casecmp(name_str).eq(zero))
        end

        # Match namespace if specified
        if ns && ns != STAR
          if @namespaces && @namespaces[ns]
            ns_uri = @namespaces[ns]
            ns_match = input.namespace.and(input.namespace.uri.eq(string(ns_uri)))
          else
            ns_match = input.namespace_name.eq(string(ns))
          end

          condition = condition ? condition.and(ns_match) : ns_match
        end

        condition
      end

      # Literal value handling

      # String literals
      def on_string(ast, *)
        string(ast.value)
      end

      # Number literals (both int and float)
      def on_number(ast, *)
        literal(ast.value.to_f.to_s)
      end

      # Current node (.)
      def on_current(ast, input)
        yield input if block_given?
        input
      end

      # Parent node (..)
      def on_parent(_ast, input)
        input.parent
      end
    end
  end
end
