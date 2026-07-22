# frozen_string_literal: true

module Moxml
  module C14n
    module Nodes
      # Attribute node.
      class AttributeNode < Node
        attr_reader :name, :value, :namespace_uri, :prefix

        def initialize(name:, value:, namespace_uri: nil, prefix: nil)
          super()
          @name = name
          @value = value
          @namespace_uri = namespace_uri
          @prefix = prefix
        end

        def node_type
          :attribute
        end

        def local_name
          name
        end

        def qname
          prefix.nil? || prefix.empty? ? name : "#{prefix}:#{name}"
        end

        # xml:* attributes (lang, space, base, id).
        def xml_attribute?
          namespace_uri == Moxml::C14n::XML_URI
        end

        # xml:lang and xml:space are inheritable per C14N 1.1 §2.4.
        def simple_inheritable?
          xml_attribute? && %w[lang space].include?(name)
        end

        def xml_id?
          xml_attribute? && name == "id"
        end

        def xml_base?
          xml_attribute? && name == "base"
        end
      end
    end
  end
end
