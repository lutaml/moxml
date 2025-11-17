# frozen_string_literal: true

module Moxml
  module XPath
    module Ruby
      # Class for converting a Ruby AST to a String.
      #
      # This class takes a {Moxml::XPath::Ruby::Node} instance and converts it
      # (and its child nodes) to a String that can be passed to `eval`.
      #
      # @private
      class Generator
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def process(ast)
          handler = :"on_#{ast.type}"
          unless respond_to?(handler, true)
            raise NotImplementedError,
                  "Generator missing handler for node type :#{ast.type}. Node: #{ast.inspect}"
          end

          send(handler, ast)
        end

        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_followed_by(ast)
          ast.to_a.map { |child| process(child) }.join("\n\n")
        end

        # Processes an assignment node.
        #
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_assign(ast)
          var, val = *ast

          var_str = process(var)
          val_str = process(val)

          "#{var_str} = #{val_str}"
        end

        # Processes a mass assignment node.
        #
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_massign(ast)
          vars, val = *ast

          var_names = vars.map { |var| process(var) }
          val_str = process(val)

          "#{var_names.join(', ')} = #{val_str}"
        end

        # Processes a `begin` node.
        #
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_begin(ast)
          body = process(ast.to_a[0])

          <<~RUBY
            begin
              #{body}
            end
          RUBY
        end

        # Processes an equality node.
        #
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_eq(ast)
          left, right = *ast

          left_str = process(left)
          right_str = process(right)

          "#{left_str} == #{right_str}"
        end

        # Processes a boolean "and" node.
        #
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_and(ast)
          left, right = *ast

          left_str = process(left)
          right_str = process(right)

          "#{left_str} && #{right_str}"
        end

        # Processes a boolean "or" node.
        #
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_or(ast)
          left, right = *ast

          left_str = process(left)
          right_str = process(right)

          "(#{left_str} || #{right_str})"
        end

        # Processes an if statement node.
        #
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_if(ast)
          cond, body, else_body = *ast

          cond_str = process(cond)
          body_str = process(body)

          if else_body
            else_str = process(else_body)

            <<~RUBY
              if #{cond_str}
                #{body_str}
              else
                #{else_str}
              end
            RUBY
          else
            <<~RUBY
              if #{cond_str}
                #{body_str}
              end
            RUBY
          end
        end

        # Processes a while statement node.
        #
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_while(ast)
          cond, body = *ast

          cond_str = process(cond)
          body_str = process(body)

          <<~RUBY
            while #{cond_str}
              #{body_str}
            end
          RUBY
        end

        # Processes a method call node.
        #
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_send(ast)
          children = ast.to_a
          receiver = children[0]
          name = children[1]
          args = children[2..-1] || []

          call = name
          brackets = name == '[]'

          unless args.empty?
            arg_strs = []
            args.each do |arg|
              result = process(arg)
              # Keep processing if we got a Node back (happens with nested send nodes)
              while result.respond_to?(:type)
                result = process(result)
              end
              arg_strs << result
            end
            arg_str = arg_strs.join(', ')
            call = brackets ? "[#{arg_str}]" : "#{call}(#{arg_str})"
          end

          if receiver
            rec_str = process(receiver)
            # Keep processing if we got a Node back
            while rec_str.respond_to?(:type)
              rec_str = process(rec_str)
            end
            call = brackets ? "#{rec_str}#{call}" : "#{rec_str}.#{call}"
          end

          call
        end

        # Processes a block node.
        #
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_block(ast)
          receiver, args, body = *ast

          receiver_str = process(receiver)
          body_str = body ? process(body) : nil
          arg_strs = args.map { |arg| process(arg) }

          <<~RUBY
            #{receiver_str} do |#{arg_strs.join(', ')}|
              #{body_str}
            end
          RUBY
        end

        # Processes a Range node.
        #
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_range(ast)
          start, stop = *ast

          start_str = process(start)
          stop_str = process(stop)

          "(#{start_str}..#{stop_str})"
        end

        # Processes a string node.
        #
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_string(ast)
          ast.to_a[0].inspect
        end

        # Processes a Symbol node.
        #
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_symbol(ast)
          ast.to_a[0].to_sym.inspect
        end

        # Processes a literal node.
        #
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_lit(ast)
          ast.to_a[0]
        end

        # Processes a constant reference node (e.g., Moxml::Document).
        #
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_const(ast)
          ast.to_a.join("::")
        end

        # Processes an array literal node.
        #
        # @param [Moxml::XPath::Ruby::Node] ast
        # @return [String]
        def on_array(ast)
          elements = ast.to_a.map { |elem| process(elem) }
          "[#{elements.join(', ')}]"
        end
      end
    end
  end
end
