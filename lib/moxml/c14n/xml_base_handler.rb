# frozen_string_literal: true

require "uri"

module Moxml
  module C14n
    # xml:base fixup handler for document subsets (C14N 1.1 §2.4).
    # Implements RFC 3986 URI joining with C14N 1.1 modifications.
    class XmlBaseHandler
      # Returns the fixed-up xml:base value to emit on the element, or
      # nil if no fixup is needed.
      def fixup_xml_base(element, omitted_ancestors)
        return nil if omitted_ancestors.empty?

        base_values = collect_base_values(element, omitted_ancestors)
        return nil if base_values.empty?

        join_base_values(base_values)
      end

      private

      def collect_base_values(element, omitted_ancestors)
        values = []
        omitted_ancestors.each do |ancestor|
          base_attr = ancestor.attribute_nodes.find(&:xml_base?)
          values << base_attr.value if base_attr
        end
        element_base = element.attribute_nodes.find(&:xml_base?)
        values << element_base.value if element_base
        values
      end

      def join_base_values(values)
        result = values.first
        values[1..].each { |ref| result = join_uri_references(result, ref) }
        result
      end

      # Join two URI references per RFC 3986 §5.2.1–5.2.4 with the
      # C14N 1.1 modification (drop fragment).
      def join_uri_references(base, ref)
        ref_parts = parse_uri(ref)
        return remove_dot_segments(ref_parts[:path] || "") if ref_parts[:scheme]

        base_parts = parse_uri(base)
        result_parts = {}

        if ref_parts[:authority]
          result_parts[:authority] = ref_parts[:authority]
          result_parts[:path] = remove_dot_segments(ref_parts[:path] || "")
          result_parts[:query] = ref_parts[:query]
        else
          if ref_parts[:path].nil? || ref_parts[:path].empty?
            result_parts[:path] = base_parts[:path]
            result_parts[:query] = ref_parts[:query] || base_parts[:query]
          elsif ref_parts[:path].start_with?("/")
            result_parts[:path] = remove_dot_segments(ref_parts[:path])
          else
            result_parts[:path] = remove_dot_segments(
              merge_paths(base_parts[:path], ref_parts[:path]),
            )
          end
          result_parts[:query] = ref_parts[:query]
          result_parts[:authority] = base_parts[:authority]
        end
        result_parts[:scheme] = base_parts[:scheme]
        reconstruct_uri(result_parts)
      end

      def parse_uri(uri_str)
        parts = {}
        if uri_str.to_s =~ %r{\A(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?\z}
          parts[:scheme] = Regexp.last_match(2)
          parts[:authority] = Regexp.last_match(4)
          parts[:path] = Regexp.last_match(5)
          parts[:query] = Regexp.last_match(7)
        end
        parts
      end

      def merge_paths(base_path, ref_path)
        if base_path&.include?("/")
          base_path.sub(%r{/[^/]*\z}, "/#{ref_path}")
        else
          ref_path
        end
      end

      # RFC 3986 §5.2.4 dot-segment removal with C14N 1.1 modifications.
      TERMINAL_DOT_SEGMENTS = %w[. ..].freeze.freeze
      private_constant :TERMINAL_DOT_SEGMENTS

      def remove_dot_segments(path)
        input = path.to_s.dup
        input = input.sub(%r{/\.\.\z}, "/../")
        output = +""

        until input.empty?
          if input.start_with?("../")
            input = input[3..]
          elsif input.start_with?("./")
            input = input[2..]
          elsif input.start_with?("/./")
            input = "/#{input[3..]}"
          elsif input == "/."
            input = "/"
          elsif input.start_with?("/../")
            input = "/#{input[4..]}"
            output = output.sub(%r{/[^/]*\z}, "")
          elsif input == "/.."
            input = "/"
            output = output.sub(%r{/[^/]*\z}, "")
          elsif TERMINAL_DOT_SEGMENTS.include?(input)
            input = ""
          else
            seg_match = input.start_with?("/") ? input.match(%r{\A(/[^/]*)}) : input.match(%r{\A([^/]*)})
            seg = seg_match[1]
            input = input[seg.length..]
            output << seg
          end
        end

        output.squeeze("/").then do |out|
          out << "/" if out.end_with?("/..")
          out
        end
      end

      def reconstruct_uri(parts)
        result = +""
        result << "#{parts[:scheme]}:" if parts[:scheme]
        result << "//#{parts[:authority]}" if parts[:authority]
        result << parts[:path].to_s if parts[:path]
        result << "?#{parts[:query]}" if parts[:query]
        result
      end
    end
  end
end
