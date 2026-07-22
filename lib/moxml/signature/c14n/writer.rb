# frozen_string_literal: true

module Moxml
  module Signature
    module C14n
      # Builds canonical octet output incrementally.
      # Output is always UTF-8 with no BOM.
      class Writer
        attr_reader :output

        def initialize
          @output = (+"")
        end

        def <<(str)
          @output << str
          self
        end

        def raw(str)
          @output << str.to_s
          self
        end

        def open_tag(prefix, local)
          @output << "<"
          @output << "#{prefix}:" unless prefix.nil? || prefix.empty?
          @output << local
          self
        end

        def close_tag_open
          @output << ">"
          self
        end

        def close_tag_self_close
          @output << "></"
          self
        end

        def close_tag(prefix, local)
          @output << "</"
          @output << "#{prefix}:" unless prefix.nil? || prefix.empty?
          @output << local
          @output << ">"
          self
        end

        def attribute(expanded_name, value)
          @output << " "
          @output << expanded_name
          @output << "=\""
          @output << C14n.escape_attribute(value)
          @output << "\""
          self
        end

        def namespace(prefix, uri)
          @output << " "
          if prefix.nil? || prefix.empty?
            @output << "xmlns"
          else
            @output << "xmlns:"
            @output << prefix
          end
          @output << "=\""
          @output << C14n.escape_attribute(uri)
          @output << "\""
          self
        end

        def text(content)
          @output << C14n.escape_text(content)
          self
        end

        def comment(content)
          @output << "<!--"
          @output << C14n.escape_text(content)
          @output << "-->"
          self
        end

        def processing_instruction(target, content)
          @output << "<?"
          @output << target
          @output << " "
          @output << content
          @output << "?>"
          self
        end
      end
    end
  end
end
