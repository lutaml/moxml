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

        # Enable debug output
        debug = ENV["DEBUG_XPATH"] == "1"
        if debug
          puts "\n#{'=' * 60}"
          puts "COMPILING XPath"
          puts "=" * 60
          puts "AST: #{ast.inspect}"
          puts
        end

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

        if debug
          puts "GENERATED RUBY CODE:"
          puts "-" * 60
          puts source
          puts "=" * 60
          puts
        end

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
        # Special cases where relative_path returns node directly:
        # - "." (current node)
        # - ".." (parent node)
        if ast.type == :relative_path && ast.children.size == 1
          child_type = ast.children[0].type
          return false if %i[current parent].include?(child_type)
        end

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
          yield input if block
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
      def on_axis(ast, input, &block)
        axis_name, test, *_predicates = ast.children

        handler = axis_name.gsub("-", "_")

        send(:"on_axis_#{handler}", test, input, &block)
      end

      # Handle step with predicates (created by parser)
      def on_step_with_predicates(ast, input, &block)
        step, *predicates = ast.children

        # If no predicates, just process the step
        return process(step, input, &block) if predicates.empty?

        # Build predicate chain: step -> pred1 -> pred2 -> ...
        # Each predicate wraps the previous result as its test
        result_ast = step

        predicates.each do |pred_wrapper|
          # pred_wrapper is :predicate node with children [expression]
          # Build proper :predicate node with [test, expression, nil]
          predicate_expr = pred_wrapper.children[0]
          result_ast = AST::Node.new(:predicate,
                                     [result_ast, predicate_expr, nil])
        end

        # Process the final chained AST
        process(result_ast, input, &block)
      end

      # AXIS: child - direct children
      def on_axis_child(ast, input)
        child = unique_literal(:child)

        document_or_node(input).if_true do
          input.children.each.add_block(child) do
            condition = process(ast, child)
            if block_given?
              condition.if_true { yield child }
            else
              condition.if_true { child }
            end
          end
        end
      end

      # AXIS: self - the node itself
      def on_axis_self(ast, input)
        condition = process(ast, input)
        if block_given?
          condition.if_true { yield input }
        else
          condition.if_true { input }
        end
      end

      # AXIS: parent - parent node
      def on_axis_parent(ast, input)
        parent = unique_literal(:parent)

        attribute_or_node(input).if_true do
          parent.assign(input.parent).followed_by do
            condition = process(ast, parent)
            if block_given?
              condition.if_true { yield parent }
            else
              condition.if_true { parent }
            end
          end
        end
      end

      # AXIS: descendant-or-self - Enables // operator
      def on_axis_descendant_or_self(ast, input)
        node = unique_literal(:descendant)
        doc_class = const_ref("Moxml", "Document")

        document_or_node(input).if_true do
          # Create a proper if-else structure that prevents double traversal
          input.is_a?(doc_class).if_true do
            # DOCUMENT PATH: test root, then traverse from root
            root = unique_literal(:root)
            root.assign(input.root).followed_by do
              root.if_true do
                # Test root first
                condition = process(ast, root)
                (if block_given?
                   condition.if_true { yield root }
                 else
                   condition.if_true { root }
                 end)
                  .followed_by do
                    # Traverse descendants FROM root only (not document.each_node)
                    root.each_node.add_block(node) do
                      desc_condition = process(ast, node)
                      if block_given?
                        desc_condition.if_true { yield node }
                      else
                        desc_condition.if_true { node }
                      end
                    end
                  end
              end
            end
          end.else do
            # NON-DOCUMENT PATH: test self, then traverse from self
            condition = process(ast, input)
            (if block_given?
               condition.if_true { yield input }
             else
               condition.if_true { input }
             end)
              .followed_by do
                # Traverse descendants FROM input
                input.each_node.add_block(node) do
                  desc_condition = process(ast, node)
                  if block_given?
                    desc_condition.if_true { yield node }
                  else
                    desc_condition.if_true { node }
                  end
                end
              end
          end
        end
      end

      # AXIS: attribute - Enables @attribute syntax
      def on_axis_attribute(ast, input)
        elem_class = const_ref("Moxml", "Element")
        attribute = unique_literal(:attribute)

        input.is_a?(elem_class).if_true do
          input.attributes.each.add_block(attribute) do
            # Use process to handle both :test and :wildcard nodes
            condition = process(ast, attribute)

            if block_given?
              condition.if_true { yield attribute }
            else
              condition.if_true { attribute }
            end
          end
        end
      end

      # AXIS: descendant - All descendant nodes (without self)
      def on_axis_descendant(ast, input)
        node = unique_literal(:descendant)

        document_or_node(input).if_true do
          input.each_node.add_block(node) do
            condition = process(ast, node)
            if block_given?
              condition.if_true { yield node }
            else
              condition.if_true { node }
            end
          end
        end
      end

      # Helper: Recursively traverse all descendants
      def traverse_all_descendants(input, &block)
        child = unique_literal(:child)

        input.children.each.add_block(child) do
          # Yield this child
          yield child
          # Then recursively traverse its descendants
          traverse_all_descendants(child, &block)
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

        # Wildcard for both name and namespace means match all - return nil
        # nil means "no additional constraint beyond type check"
        return nil if name == STAR && (!ns || ns == STAR)

        condition = nil
        name_str = string(name)
        zero = literal(0)

        # Match name (case-insensitive) unless wildcard
        if name != STAR
          # If we have a namespace prefix, we need to compare local names
          # For elements like "ns:item", we should compare against "item" not "ns:item"
          if ns && ns != STAR && @namespaces && @namespaces[ns]
            # Extract local name by splitting on ':' and taking the last part
            # This handles both "ns:item" -> "item" and "item" -> "item"
            local_name_expr = input.name.split(string(":")).last
            condition = local_name_expr.eq(name_str)
              .or(local_name_expr.casecmp(name_str).eq(zero))
          else
            # No namespace or no mapping - compare full name
            condition = input.name.eq(name_str)
              .or(input.name.casecmp(name_str).eq(zero))
          end
        end

        # Match namespace if specified
        if ns && ns != STAR
          if @namespaces && @namespaces[ns]
            # Resolve prefix to URI using namespace mappings
            ns_uri = @namespaces[ns]
            ns_match = input.namespace.and(input.namespace.uri.eq(string(ns_uri)))
          else
            # No mapping provided - check against element's namespace prefix
            # Need to ensure input.namespace exists first
            ns_match = input.namespace.and(input.namespace.prefix.eq(string(ns)))
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
      def on_current(_ast, input)
        if block_given?
          yield input # Block returns Ruby::Node for matched.push(input)
        else
          input
        end
      end

      # Parent node (..)
      def on_parent(_ast, input)
        input.parent
      end

      # ===== OPERATORS =====

      # Comparison: = (equality)
      def on_eq(ast, input, &block)
        conv = literal(Moxml::XPath::Conversion)

        operator(ast, input) do |left, right|
          mass_assign([left, right], conv.to_compatible_types(left, right))
            .followed_by do
              operation = left.eq(right)

              block ? operation.if_true(&block) : operation
            end
        end
      end

      # Comparison: != (inequality)
      def on_neq(ast, input, &block)
        conv = literal(Moxml::XPath::Conversion)

        operator(ast, input) do |left, right|
          mass_assign([left, right], conv.to_compatible_types(left, right))
            .followed_by do
              operation = left != right

              block ? operation.if_true(&block) : operation
            end
        end
      end

      # Comparison: < (less than)
      def on_lt(ast, input, &block)
        conversion = literal(Moxml::XPath::Conversion)

        operator(ast, input) do |left, right|
          lval = conversion.to_float(left)
          rval = conversion.to_float(right)
          operation = lval < rval

          block ? conversion.to_boolean(operation).if_true(&block) : operation
        end
      end

      # Comparison: > (greater than)
      def on_gt(ast, input, &block)
        conversion = literal(Moxml::XPath::Conversion)

        operator(ast, input) do |left, right|
          lval = conversion.to_float(left)
          rval = conversion.to_float(right)
          operation = lval > rval

          block ? conversion.to_boolean(operation).if_true(&block) : operation
        end
      end

      # Comparison: <= (less than or equal)
      def on_lte(ast, input, &block)
        conversion = literal(Moxml::XPath::Conversion)

        operator(ast, input) do |left, right|
          lval = conversion.to_float(left)
          rval = conversion.to_float(right)
          operation = lval <= rval

          block ? conversion.to_boolean(operation).if_true(&block) : operation
        end
      end

      # Comparison: >= (greater than or equal)
      def on_gte(ast, input, &block)
        conversion = literal(Moxml::XPath::Conversion)

        operator(ast, input) do |left, right|
          lval = conversion.to_float(left)
          rval = conversion.to_float(right)
          operation = lval >= rval

          block ? conversion.to_boolean(operation).if_true(&block) : operation
        end
      end

      # Arithmetic: + (addition)
      def on_add(ast, input, &block)
        conversion = literal(Moxml::XPath::Conversion)

        operator(ast, input) do |left, right|
          lval = conversion.to_float(left)
          rval = conversion.to_float(right)
          operation = lval + rval

          block ? conversion.to_boolean(operation).if_true(&block) : operation
        end
      end

      # Arithmetic: - (subtraction)
      def on_sub(ast, input, &block)
        conversion = literal(Moxml::XPath::Conversion)

        operator(ast, input) do |left, right|
          lval = conversion.to_float(left)
          rval = conversion.to_float(right)
          operation = lval - rval

          block ? conversion.to_boolean(operation).if_true(&block) : operation
        end
      end

      # Arithmetic: * (multiplication)
      def on_mul(ast, input, &block)
        conversion = literal(Moxml::XPath::Conversion)

        operator(ast, input) do |left, right|
          lval = conversion.to_float(left)
          rval = conversion.to_float(right)
          operation = lval * rval

          block ? conversion.to_boolean(operation).if_true(&block) : operation
        end
      end

      # Arithmetic: div (division)
      def on_div(ast, input, &block)
        conversion = literal(Moxml::XPath::Conversion)

        operator(ast, input) do |left, right|
          lval = conversion.to_float(left)
          rval = conversion.to_float(right)
          operation = lval / rval

          block ? conversion.to_boolean(operation).if_true(&block) : operation
        end
      end

      # Arithmetic: mod (modulo)
      def on_mod(ast, input, &block)
        conversion = literal(Moxml::XPath::Conversion)

        operator(ast, input) do |left, right|
          lval = conversion.to_float(left)
          rval = conversion.to_float(right)
          operation = lval % rval

          block ? conversion.to_boolean(operation).if_true(&block) : operation
        end
      end

      # Unary: minus (negation)
      def on_minus(ast, input, &block)
        operand = ast.children[0]
        operand_ast = process(operand, input)
        conversion = literal(Moxml::XPath::Conversion)

        operand_var = unique_literal(:unary_operand)
        operand_var.assign(operand_ast)
          .followed_by do
            negated = literal(0) - conversion.to_float(operand_var)
            block ? conversion.to_boolean(negated).if_true(&block) : negated
          end
      end

      # Logical: and
      def on_and(ast, input, &block)
        conversion = literal(Moxml::XPath::Conversion)

        operator(ast, input) do |left, right|
          lval = conversion.to_boolean(left)
          rval = conversion.to_boolean(right)
          operation = lval.and(rval)

          block ? conversion.to_boolean(operation).if_true(&block) : operation
        end
      end

      # Logical: or
      def on_or(ast, input, &block)
        conversion = literal(Moxml::XPath::Conversion)

        operator(ast, input) do |left, right|
          lval = conversion.to_boolean(left)
          rval = conversion.to_boolean(right)
          operation = lval.or(rval)

          block ? conversion.to_boolean(operation).if_true(&block) : operation
        end
      end

      # Union: | (pipe)
      def on_pipe(ast, input)
        left, right = ast.children

        union = unique_literal(:union)
        context_var = context_literal

        # Create NodeSet for union results
        nodeset_class = const_ref("Moxml", "NodeSet")
        empty_array = Ruby::Node.new(:array, [])

        # Expressions such as "a | b | c"
        if left.type == :pipe
          union.assign(process(left, input))
            .followed_by(process(right, input) { |node| union << node })
            .followed_by(union)
        # Expressions such as "a | b"
        else
          nodeset_new = Ruby::Node.new(:send,
                                       [nodeset_class, "new", empty_array,
                                        context_var])

          union.assign(nodeset_new)
            .followed_by(process(left, input) { |node| union << node })
            .followed_by(process(right, input) { |node| union << node })
            .followed_by(union)
        end
      end

      # Variable: $variable
      def on_var(ast, *)
        name = ast.children[0]

        variables_literal.and(variables_literal[string(name)])
          .or(send_message(:raise, string("Undefined XPath variable: #{name}")))
      end

      # Predicate handling: //book[@price < 20]
      def on_predicate(ast, input, &block)
        test, predicate, following = ast.children

        index_var = unique_literal(:index)

        # Check predicate type to determine strategy
        method = if number?(predicate)
                   :on_predicate_index
                 elsif has_call_node?(predicate, "last")
                   :on_predicate_temporary
                 else
                   :on_predicate_direct
                 end

        @predicate_indexes << index_var

        result = index_var.assign(literal(1)).followed_by do
          send(method, input, test, predicate) do |matched|
            if following
              process(following, matched, &block)
            else
              yield matched
            end
          end
        end

        @predicate_indexes.pop

        result
      end

      # Predicate that requires temporary NodeSet (for last())
      def on_predicate_temporary(input, test, predicate)
        temp_set = unique_literal(:temp_set)
        pred_node = unique_literal(:pred_node)
        pred_var = unique_literal(:pred_var)
        conversion = literal(Moxml::XPath::Conversion)
        context_var = context_literal

        index_var = predicate_index
        index_step = literal(1)

        @predicate_nodesets << temp_set

        # Create NodeSet for temp results
        nodeset_class = const_ref("Moxml", "NodeSet")
        empty_array = Ruby::Node.new(:array, [])
        nodeset_new = Ruby::Node.new(:send,
                                     [nodeset_class, "new", empty_array,
                                      context_var])

        ast = temp_set.assign(nodeset_new)
          .followed_by do
            process(test, input) { |node| temp_set << node }
          end
          .followed_by do
            temp_set.each.add_block(pred_node) do
              pred_ast = process(predicate, pred_node)

              pred_var.assign(pred_ast)
                .followed_by do
                  pred_var.is_a?(literal(:Numeric)).if_true do
                    pred_var.assign(pred_var.to_i.eq(index_var))
                  end
                end
                .followed_by do
                  conversion.to_boolean(pred_var).if_true { yield pred_node }
                end
                .followed_by do
                  index_var.assign(index_var + index_step)
                end
            end
          end

        @predicate_nodesets.pop

        ast
      end

      # Predicate that doesn't require temporary NodeSet
      def on_predicate_direct(input, test, predicate)
        pred_var = unique_literal(:pred_var)
        index_var = predicate_index
        index_step = literal(1)
        conversion = literal(Moxml::XPath::Conversion)

        process(test, input) do |matched_test_node|
          pred_ast = if return_nodeset?(predicate)
                       # Use catch/throw for early return
                       catch_message(:predicate_matched) do
                         process(predicate, matched_test_node) do
                           throw_message(:predicate_matched, self_true)
                         end
                       end
                     else
                       process(predicate, matched_test_node)
                     end

          pred_var.assign(pred_ast)
            .followed_by do
              pred_var.is_a?(literal(:Numeric)).if_true do
                pred_var.assign(pred_var.to_i.eq(index_var))
              end
            end
            .followed_by do
              conversion.to_boolean(pred_var).if_true do
                yield matched_test_node
              end
            end
            .followed_by do
              index_var.assign(index_var + index_step)
            end
        end
      end

      # Predicate with literal index: //book[1]
      def on_predicate_index(input, test, predicate)
        index_var = predicate_index
        index_step = literal(1)

        index = process(predicate, input).to_i

        process(test, input) do |matched_test_node|
          index_var.eq(index)
            .if_true do
              yield matched_test_node
            end
            .followed_by do
              index_var.assign(index_var + index_step)
            end
        end
      end

      # ===== XPATH FUNCTIONS =====

      # XPath function dispatcher
      def on_call(ast, input, &block)
        name, *args = ast.children

        handler = name.gsub("-", "_")

        send(:"on_call_#{handler}", input, *args, &block)
      end

      # 1. string() - Convert value to string
      def on_call_string(input, arg = nil)
        convert_var = unique_literal(:convert)
        conversion = literal(Moxml::XPath::Conversion)

        argument_or_first_node(input, arg) do |arg_var|
          convert_var.assign(conversion.to_string(arg_var))
            .followed_by do
              if block_given?
                convert_var.empty?.if_false { yield convert_var }
              else
                convert_var
              end
            end
        end
      end

      # 2. concat() - Concatenate strings
      def on_call_concat(input, *args)
        conversion = literal(Moxml::XPath::Conversion)
        assigns = []
        conversions = []

        args.each do |arg|
          arg_var = unique_literal(:concat_arg)
          arg_ast = try_match_first_node(arg, input)

          assigns << arg_var.assign(arg_ast)
          conversions << conversion.to_string(arg_var)
        end

        concatted = assigns.inject(:followed_by)
          .followed_by(conversions.inject(:+))

        block_given? ? concatted.empty?.if_false { yield concatted } : concatted
      end

      # 3. starts-with() - Check string prefix
      def on_call_starts_with(input, haystack, needle)
        haystack_var = unique_literal(:haystack)
        needle_var = unique_literal(:needle)
        conversion = literal(Moxml::XPath::Conversion)

        haystack_var.assign(try_match_first_node(haystack, input))
          .followed_by do
            needle_var.assign(try_match_first_node(needle, input))
          end
          .followed_by do
            haystack_var.assign(conversion.to_string(haystack_var))
              .followed_by do
                needle_var.assign(conversion.to_string(needle_var))
              end
              .followed_by do
                equal = needle_var.empty?
                  .or(haystack_var.start_with?(needle_var))

                block_given? ? equal.if_true { yield equal } : equal
              end
          end
      end

      # 4. contains() - Check substring
      def on_call_contains(input, haystack, needle)
        haystack_lit = unique_literal(:haystack)
        needle_lit = unique_literal(:needle)
        conversion = literal(Moxml::XPath::Conversion)

        haystack_lit.assign(try_match_first_node(haystack, input))
          .followed_by do
            needle_lit.assign(try_match_first_node(needle, input))
          end
          .followed_by do
            converted = conversion.to_string(haystack_lit)
              .include?(conversion.to_string(needle_lit))

            block_given? ? converted.if_true { yield converted } : converted
          end
      end

      # 5. substring-before() - Get part before separator
      def on_call_substring_before(input, haystack, needle)
        haystack_var = unique_literal(:haystack)
        needle_var = unique_literal(:needle)
        conversion = literal(Moxml::XPath::Conversion)

        before = unique_literal(:before)
        sep = unique_literal(:sep)
        after = unique_literal(:after)

        haystack_var.assign(try_match_first_node(haystack, input))
          .followed_by do
            needle_var.assign(try_match_first_node(needle, input))
          end
          .followed_by do
            converted = conversion.to_string(haystack_var)
              .partition(conversion.to_string(needle_var))

            mass_assign([before, sep, after], converted).followed_by do
              sep.empty?
                .if_true { sep }
                .else { block_given? ? yield : before }
            end
          end
      end

      # 6. substring-after() - Get part after separator
      def on_call_substring_after(input, haystack, needle)
        haystack_var = unique_literal(:haystack)
        needle_var = unique_literal(:needle)
        conversion = literal(Moxml::XPath::Conversion)

        before = unique_literal(:before)
        sep = unique_literal(:sep)
        after = unique_literal(:after)

        haystack_var.assign(try_match_first_node(haystack, input))
          .followed_by do
            needle_var.assign(try_match_first_node(needle, input))
          end
          .followed_by do
            converted = conversion.to_string(haystack_var)
              .partition(conversion.to_string(needle_var))

            mass_assign([before, sep, after], converted).followed_by do
              sep.empty?
                .if_true { sep }
                .else { block_given? ? yield : after }
            end
          end
      end

      # 7. substring() - Extract substring
      def on_call_substring(input, haystack, start, length = nil)
        haystack_var = unique_literal(:haystack)
        start_var = unique_literal(:start)
        length_var = unique_literal(:length)
        result_var = unique_literal(:result)
        ruby_start = unique_literal(:ruby_start)
        effective_length = unique_literal(:effective_length)
        conversion = literal(Moxml::XPath::Conversion)

        haystack_var.assign(try_match_first_node(haystack, input))
          .followed_by do
            haystack_var.assign(conversion.to_string(haystack_var))
          end
          .followed_by do
            start_var.assign(try_match_first_node(start, input))
              .followed_by do
                # Round the start position first (XPath 1.0 spec requires rounding)
                start_var.assign(conversion.to_float(start_var).round.to_i)
              end
          end
          .followed_by do
            if length
              length_var.assign(try_match_first_node(length, input))
                .followed_by do
                  # Round the length (XPath 1.0 spec requires rounding)
                  length_var.assign(conversion.to_float(length_var).round.to_i)
                end
                .followed_by do
                  # XPath 1.0 algorithm:
                  # If start < 1, some positions fall before the string
                  # We need to adjust the effective length accordingly
                  # effective_length = (start + length) - max(start, 1)
                  # lua_start = max(start, 1) - 1 (since we start from position 1)

                  # Calculate how many positions to skip before position 1
                  # If start is 0, we lose 1 position; if -2, we lose 3 positions
                  ruby_start.assign(
                    (start_var < literal(1))
                      .if_true { literal(0) }
                      .else { start_var - literal(1) },
                  )
                end
                .followed_by do
                  # Calculate effective length accounting for positions before string
                  effective_length.assign(
                    (start_var < literal(1))
                      .if_true do
                        # Some positions are before position 1
                        # end_pos = start + length
                        # effective = end_pos - 1 (since we start from position 1)
                        # But clamp to 0 if entirely before string
                        ((start_var + length_var) - literal(1))
                          .if_true { (start_var + length_var) - literal(1) }
                          .else { literal(0) }
                      end
                      .else { length_var },
                  )
                end
                .followed_by do
                  # Clamp effective length to non-negative
                  effective_length.assign(
                    (effective_length < literal(0))
                      .if_true { literal(0) }
                      .else { effective_length },
                  )
                end
                .followed_by do
                  # Extract substring with effective length
                  result_var.assign(haystack_var[ruby_start, effective_length])
                    .followed_by do
                      # Ensure we return empty string instead of nil
                      result_var.assign(result_var.if_true do
                        result_var
                      end.else { string("") })
                    end
                end
                .followed_by do
                  if block_given?
                    result_var.empty?.if_false do
                      yield result_var
                    end
                  else
                    result_var
                  end
                end
            else
              # No length specified - go to end of string
              # Convert to 0-based index, clamping to 0
              ruby_start.assign(
                (start_var < literal(1))
                  .if_true { literal(0) }
                  .else { start_var - literal(1) },
              ).followed_by do
                # Extract from start to end
                result_var.assign(haystack_var[range(ruby_start, literal(-1))])
                  .followed_by do
                    # Ensure we return empty string instead of nil
                    result_var.assign(result_var.if_true do
                      result_var
                    end.else { string("") })
                  end
              end
                .followed_by do
                  if block_given?
                    result_var.empty?.if_false do
                      yield result_var
                    end
                  else
                    result_var
                  end
                end
            end
          end
      end

      # 8. string-length() - Get string length
      def on_call_string_length(input, arg = nil)
        convert_var = unique_literal(:convert)
        conversion = literal(Moxml::XPath::Conversion)

        argument_or_first_node(input, arg) do |arg_var|
          convert_var.assign(conversion.to_string(arg_var).length)
            .followed_by do
              if block_given?
                convert_var.zero?.if_false { yield convert_var }
              else
                convert_var.to_f
              end
            end
        end
      end

      # 9. normalize-space() - Normalize whitespace
      def on_call_normalize_space(input, arg = nil)
        conversion = literal(Moxml::XPath::Conversion)
        norm_var = unique_literal(:normalized)

        # Create regex for matching whitespace sequences
        # Use Regexp.new to create /\s+/ pattern at runtime
        regexp_class = const_ref("Regexp")
        whitespace_pattern = string('\\s+')
        whitespace_regex = Ruby::Node.new(:send,
                                          [regexp_class, "new",
                                           whitespace_pattern])
        replace = string(" ")

        argument_or_first_node(input, arg) do |arg_var|
          norm_var
            .assign(conversion.to_string(arg_var).strip.gsub(whitespace_regex,
                                                             replace))
            .followed_by do
              norm_var.empty?
                .if_true { string("") }
                .else { block_given? ? yield : norm_var }
            end
        end
      end

      # 10. translate() - Character replacement
      def on_call_translate(input, source, find, replace)
        source_var = unique_literal(:source)
        find_var = unique_literal(:find)
        replace_var = unique_literal(:replace)
        replaced_var = unique_literal(:replaced)
        conversion = literal(Moxml::XPath::Conversion)

        char = unique_literal(:char)
        index = unique_literal(:index)

        source_var.assign(try_match_first_node(source, input))
          .followed_by do
            replaced_var.assign(conversion.to_string(source_var))
          end
          .followed_by do
            find_var.assign(try_match_first_node(find, input))
          end
          .followed_by do
            find_var.assign(conversion.to_string(find_var).chars.to_array)
          end
          .followed_by do
            replace_var.assign(try_match_first_node(replace, input))
          end
          .followed_by do
            replace_var.assign(conversion.to_string(replace_var).chars.to_array)
          end
          .followed_by do
            find_var.each_with_index.add_block(char, index) do
              replace_with = replace_var[index]
                .if_true { replace_var[index] }
                .else { string("") }

              replaced_var.assign(replaced_var.gsub(char, replace_with))
            end
          end
          .followed_by { replaced_var }
      end

      # ===== NUMERIC FUNCTIONS =====

      # 1. number() - Convert to number
      def on_call_number(input, arg = nil, &block)
        convert_var = unique_literal(:convert)
        conversion = literal(Moxml::XPath::Conversion)

        argument_or_first_node(input, arg) do |arg_var|
          convert_var.assign(conversion.to_float(arg_var)).followed_by do
            if block
              convert_var.zero?.if_false(&block)
            else
              convert_var
            end
          end
        end
      end

      # 2. sum() - Sum node values
      def on_call_sum(input, arg, &block)
        unless return_nodeset?(arg)
          raise TypeError, "sum() can only operate on a path, axis or predicate"
        end

        sum_var = unique_literal(:sum)
        conversion = literal(Moxml::XPath::Conversion)

        sum_var.assign(literal(0.0))
          .followed_by do
            process(arg, input) do |matched_node|
              sum_var.assign(sum_var + conversion.to_float(matched_node.text))
            end
          end
          .followed_by do
            block ? sum_var.zero?.if_false(&block) : sum_var
          end
      end

      # 3. count() - Count nodes
      def on_call_count(input, arg, &block)
        count = unique_literal(:count)

        unless return_nodeset?(arg)
          raise TypeError, "count() can only operate on NodeSet instances"
        end

        count.assign(literal(0.0))
          .followed_by do
            process(arg, input) { count.assign(count + literal(1)) }
          end
          .followed_by do
            block ? count.zero?.if_false(&block) : count
          end
      end

      # 4. floor() - Round down
      def on_call_floor(input, arg)
        arg_ast = try_match_first_node(arg, input)
        call_arg = unique_literal(:call_arg)
        conversion = literal(Moxml::XPath::Conversion)

        call_arg.assign(arg_ast)
          .followed_by do
            call_arg.assign(conversion.to_float(call_arg))
          end
          .followed_by do
            call_arg.nan?
              .if_true { call_arg }
              .else { block_given? ? yield : call_arg.floor.to_f }
          end
      end

      # 5. ceiling() - Round up
      def on_call_ceiling(input, arg)
        arg_ast = try_match_first_node(arg, input)
        call_arg = unique_literal(:call_arg)
        conversion = literal(Moxml::XPath::Conversion)

        call_arg.assign(arg_ast)
          .followed_by do
            call_arg.assign(conversion.to_float(call_arg))
          end
          .followed_by do
            call_arg.nan?
              .if_true { call_arg }
              .else { block_given? ? yield : call_arg.ceil.to_f }
          end
      end

      # 6. round() - Round to nearest
      def on_call_round(input, arg)
        arg_ast = try_match_first_node(arg, input)
        call_arg = unique_literal(:call_arg)
        conversion = literal(Moxml::XPath::Conversion)

        call_arg.assign(arg_ast)
          .followed_by do
            call_arg.assign(conversion.to_float(call_arg))
          end
          .followed_by do
            call_arg.nan?
              .if_true { call_arg }
              .else { block_given? ? yield : call_arg.round.to_f }
          end
      end

      # ===== BOOLEAN FUNCTIONS =====

      # 1. boolean() - Convert to boolean
      def on_call_boolean(input, arg, &block)
        arg_ast = try_match_first_node(arg, input)
        call_arg = unique_literal(:call_arg)
        conversion = literal(Moxml::XPath::Conversion)

        call_arg.assign(arg_ast).followed_by do
          converted = conversion.to_boolean(call_arg)

          block ? converted.if_true(&block) : converted
        end
      end

      # 2. not() - Negate boolean
      def on_call_not(input, arg, &block)
        arg_ast = try_match_first_node(arg, input)
        call_arg = unique_literal(:call_arg)
        conversion = literal(Moxml::XPath::Conversion)

        call_arg.assign(arg_ast).followed_by do
          converted = conversion.to_boolean(call_arg).not

          block ? converted.if_true(&block) : converted
        end
      end

      # 3. true() - Return true
      def on_call_true(*)
        block_given? ? yield : self_true
      end

      # 4. false() - Return false
      def on_call_false(*)
        self_false
      end

      # ===== NODE FUNCTIONS =====

      # 1. local-name() - Get local name without namespace prefix
      def on_call_local_name(input, arg = nil)
        argument_or_first_node(input, arg) do |arg_var|
          arg_var
            .if_true do
              ensure_element_or_attribute(arg_var)
                .followed_by { block_given? ? yield : arg_var.name }
            end
            .else { string("") }
        end
      end

      # 2. name() - Get expanded/qualified name with namespace
      def on_call_name(input, arg = nil)
        argument_or_first_node(input, arg) do |arg_var|
          arg_var
            .if_true do
              ensure_element_or_attribute(arg_var)
                .followed_by { block_given? ? yield : arg_var.expanded_name }
            end
            .else { string("") }
        end
      end

      # 3. namespace-uri() - Get namespace URI
      def on_call_namespace_uri(input, arg = nil)
        default = string("")

        argument_or_first_node(input, arg) do |arg_var|
          arg_var
            .if_true do
              ensure_element_or_attribute(arg_var).followed_by do
                arg_var.namespace
                  .if_true { block_given? ? yield : arg_var.namespace.uri }
                  .else { default }
              end
            end
            .else { default }
        end
      end

      # 4. lang() - Check xml:lang attribute
      def on_call_lang(input, arg)
        lang_var = unique_literal("lang")
        node = unique_literal("node")
        found = unique_literal("found")
        xml_lang = unique_literal("xml_lang")
        matched = unique_literal("matched")

        conversion = literal(Moxml::XPath::Conversion)

        ast = lang_var.assign(try_match_first_node(arg, input))
          .followed_by do
            lang_var.assign(conversion.to_string(lang_var))
          end
          .followed_by do
            matched.assign(self_false)
          end
          .followed_by do
            node.assign(input)
          end
          .followed_by do
            xml_lang.assign(string("xml:lang"))
          end
          .followed_by do
            node.respond_to?(symbol(:attribute)).while_true do
              found.assign(node.get(xml_lang))
                .followed_by do
                  found.if_true do
                    found.eq(lang_var)
                      .if_true do
                        if block_given?
                          yield
                        else
                          matched.assign(self_true).followed_by(break_loop)
                        end
                      end
                      .else { break_loop }
                  end
                end
                .followed_by(node.assign(node.parent))
            end
          end

        block_given? ? ast : ast.followed_by(matched)
      end

      # ===== POSITION FUNCTIONS =====

      # 1. position() - Current position in predicate context
      def on_call_position(*)
        index = predicate_index

        unless index
          raise InvalidContextError.new(
            "position() requires a predicate context. " \
            "Use position() within a predicate like: //item[position() = 1]",
            function_name: "position()",
            required_context: "predicate",
          )
        end

        index.to_f
      end

      # 2. last() - Size of current predicate context
      def on_call_last(*)
        set = predicate_nodeset

        unless set
          raise InvalidContextError.new(
            "last() requires a predicate context. " \
            "Use last() within a predicate like: //item[position() = last()]",
            function_name: "last()",
            required_context: "predicate",
          )
        end

        set.length.to_f
      end

      # ===== SPECIAL FUNCTIONS =====

      # 1. id() - Find nodes by ID attribute
      def on_call_id(input, arg)
        orig_input = original_input_literal
        node = unique_literal(:node)
        ids_var = unique_literal("ids")
        matched = unique_literal("id_matched")
        id_str_var = unique_literal("id_string")
        attr_var = unique_literal("attr")

        nodeset_class = const_ref("Moxml", "NodeSet")
        context_var = context_literal
        empty_array = Ruby::Node.new(:array, [])

        matched.assign(Ruby::Node.new(:send,
                                      [nodeset_class, "new", empty_array,
                                       context_var]))
          .followed_by do
            # When using a path, get text of all matched nodes
            if return_nodeset?(arg)
              empty_ids = Ruby::Node.new(:array, [])
              ids_var.assign(empty_ids).followed_by do
                process(arg, input) { |element| ids_var << element.text }
              end
            # Otherwise cast to string and split on spaces
            else
              conversion = literal(Moxml::XPath::Conversion)
              ids_var.assign(process(arg, input))
                .followed_by do
                  ids_var.assign(conversion.to_string(ids_var).split(string(" ")))
                end
            end
          end
          .followed_by do
            id_str_var.assign(string("id"))
          end
          .followed_by do
            orig_input.each_node.add_block(node) do
              node.is_a?(const_ref("Moxml", "Element")).if_true do
                attr_var.assign(node.attribute(id_str_var)).followed_by do
                  attr_var.and(ids_var.include?(attr_var.value))
                    .if_true { block_given? ? yield : matched << node }
                end
              end
            end
          end
          .followed_by(matched)
      end

      # Helper methods

      # Helper: Get argument or use current node's first child
      def argument_or_first_node(input, arg = nil)
        arg_ast = arg ? try_match_first_node(arg, input) : input
        arg_var = unique_literal(:argument_or_first_node)

        arg_var.assign(arg_ast).followed_by { yield arg_var }
      end

      # Helper: Try to match first node v1
      def try_match_first_node_v1(ast, input, optimize_first = true)
        if return_nodeset?(ast) && optimize_first
          matched_set = unique_literal(:matched_set)
          first_node = unique_literal(:first_node)
          context_var = context_literal

          # Create NodeSet for results
          nodeset_class = const_ref("Moxml", "NodeSet")
          empty_array = Ruby::Node.new(:array, [])
          nodeset_new = Ruby::Node.new(:send,
                                       [nodeset_class, "new", empty_array,
                                        context_var])

          matched_set.assign(nodeset_new)
            .followed_by do
              # Process with block to accumulate results
              process(ast, input) { |node| matched_set.push(node) }
            end
            .followed_by do
              first_node.assign(matched_set[literal(0)])
            end
            .followed_by do
              first_node.if_true { first_node }.else { string("") }
            end
        else
          process(ast, input)
        end
      end

      # Helper: Create mass assignment node
      def mass_assign(vars, value)
        Ruby::Node.new(:massign, [vars, value])
      end

      # Helper: Create range node for Ruby AST
      def range(start, stop)
        Ruby::Node.new(:range, [start, stop])
      end

      # Helper: Ensure node is Element or Attribute
      def ensure_element_or_attribute(input)
        element_or_attribute(input).if_false do
          raise_message(TypeError, "argument is not an Element or Attribute")
        end
      end

      # Helper: Raise an error with message
      def raise_message(klass, message)
        send_message(:raise, literal(klass), string(message))
      end

      # Helper: Send a message (for method calls like raise, break)
      def send_message(name, *args)
        Ruby::Node.new(:send, [nil, name.to_s] + args)
      end

      # Helper: Break statement
      def break_loop
        send_message(:break)
      end

      # Helper: Get current predicate index
      def predicate_index
        @predicate_indexes.last
      end

      # Helper: Get current predicate nodeset
      def predicate_nodeset
        @predicate_nodesets.last
      end

      # Helper: Get original input literal for traversal
      def original_input_literal
        literal(:node)
      end

      # Helper: Generate code for an operator
      #
      # Processes left and right operands, optimizing to match only first node
      # when appropriate (path, axis, predicate)
      def operator(ast, input, optimize_first = true)
        left, right = ast.children

        left_var = unique_literal(:op_left)
        right_var = unique_literal(:op_right)

        left_ast = try_match_first_node(left, input, optimize_first)
        right_ast = try_match_first_node(right, input, optimize_first)

        left_var.assign(left_ast)
          .followed_by(right_var.assign(right_ast))
          .followed_by { yield left_var, right_var }
      end

      # Helper: Try to match first node in a set, otherwise process as usual
      def try_match_first_node(ast, input, optimize_first = true)
        if return_nodeset?(ast) && optimize_first
          matched_set = unique_literal(:matched_set)
          first_node = unique_literal(:first_node)
          context_var = context_literal

          # Create NodeSet for results
          nodeset_class = const_ref("Moxml", "NodeSet")
          empty_array = Ruby::Node.new(:array, [])
          nodeset_new = Ruby::Node.new(:send,
                                       [nodeset_class, "new", empty_array,
                                        context_var])

          matched_set.assign(nodeset_new)
            .followed_by do
              # Process with block to accumulate results
              process(ast, input) { |node| matched_set.push(node) }
            end
            .followed_by do
              first_node.assign(matched_set[literal(0)])
            end
            .followed_by { first_node }
        else
          process(ast, input)
        end
      end

      # Helper: Check if AST node is a number
      def number?(ast)
        %i[int float number].include?(ast.type)
      end

      # Helper: Check if AST contains a call node with given name
      def has_call_node?(ast, name)
        visit = [ast]

        until visit.empty?
          current = visit.pop

          return true if current.type == :call && current.children[0] == name

          current.children.each do |child|
            visit << child if child.is_a?(AST::Node)
          end
        end

        false
      end

      # Helper: Catch a message (for early returns)
      def catch_message(name)
        send_message(:catch, symbol(name)).add_block do
          # Ensure catch only returns value when throw is invoked
          yield.followed_by(self_nil)
        end
      end

      # Helper: Throw a message with optional arguments
      def throw_message(name, *args)
        send_message(:throw, symbol(name), *args)
      end

      # Helper: Variables literal for variable support
      def variables_literal
        literal(:variables)
      end
    end
  end
end
