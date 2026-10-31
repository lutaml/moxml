# frozen_string_literal: true

module Moxml
  # Executable reference semantics (TODO.sota/03): a pure-Ruby XML
  # reader, writer, and normalizer that answer the processing model
  # without any native engine. Adapters are differentially tested
  # against these answers; the reference is also the lane for
  # engine-free environments.
  #
  # The reference is deliberately small and total over the model's
  # declared input taxonomy — every well-formed document the model
  # admits is parseable here. It is an oracle, not a production
  # parser: no recovery, no diagnostics beyond a named ParseError.
  module Reference
    autoload :Parser, "moxml/reference/parser"
    autoload :Writer, "moxml/reference/writer"
    autoload :Normalizer, "moxml/reference/normalizer"

    # A reference node: the information set of the processing model,
    # with no engine-specific shape.
    class Node
      attr_accessor :kind, :name, :attributes, :children, :data, :parent

      def initialize(kind:, name: nil, data: nil, attributes: [])
        @kind = kind
        @name = name
        @data = data
        @attributes = attributes
        @children = []
        @parent = nil
      end

      def element?
        @kind == :element
      end

      def text?
        @kind == :text
      end

      # The facade's name face: a bare local name for prefixed sources
      # (Element#name; attribute pairs list bare names too).
      def local_name
        return @name unless @name&.include?(":")

        @name.split(":", 2)[1]
      end

      # Concatenated descendant text (elements; text and CDATA only —
      # comments and PI data are not text); own data for text-like
      # nodes (the model's `text` face).
      def text
        case @kind
        when :element
          @children.select do |child|
            child.kind == :text || child.kind == :cdata || child.element?
          end.map(&:text).join
        when :text, :cdata
          @data
        else
          ""
        end
      end

      # Element content is its text face; text-like nodes answer their
      # data (PI data excludes the separator, per the model).
      def content
        element? ? text : @data
      end

      def attribute(name)
        pair = @attributes.find do |(key, _)|
          key == name || local_name_of(key) == name
        end
        pair && pair[1]
      end

      # The facade's listing face: bare names, source order, duplicates
      # included, namespace declarations excluded (they are Namespace
      # nodes, not attributes — uniform with every adapter).
      def attribute_pairs
        @attributes.filter_map do |(key, value)|
          next if key == "xmlns" || key.start_with?("xmlns:")

          [local_name_of(key), value]
        end
      end

      def local_name_of(name)
        return name unless name&.include?(":")

        name.split(":", 2)[1]
      end
    end

    # A reference document: declaration and doctype are state (the
    # model's document-parts-are-state rule); children are the
    # top-level nodes excluding them.
    class Document
      attr_accessor :children, :declaration, :doctype, :entities

      def initialize
        @children = []
        @declaration = nil
        @doctype = nil
        @entities = {}
      end

      def root
        @children.find(&:element?)
      end

      # Depth-first pre-order, excluding the document itself.
      def each_node(&block)
        @children.each { |child| walk(child, &block) }
      end

      def walk(node, &block)
        yield node
        node.children.each { |child| walk(child, &block) }
      end
    end

    # Encodings the reference accepts: UTF-8 and US-ASCII sources.
    # Transcoding is the adapter's business; the reference reads the
    # UTF-8 string the facade hands it.
    module_function

    # Parse an XML string into a reference Document.
    def parse(xml)
      Parser.new(xml).parse
    end

    # Document-order element names (the ordering face; bare local
    # names, matching Element#name).
    def element_names(document)
      names = []
      document.each_node { |node| names << node.local_name if node.element? }
      names
    end

    # Element children names, keyed by each element's index in
    # pre-order (the children-listing face; avoids text segmentation,
    # which is a registered engine divergence family).
    def child_element_names(document)
      rows = []
      document.each_node do |node|
        next unless node.element?

        rows << node.children.select(&:element?).map(&:local_name)
      end
      rows
    end

    # The access truth table, one row per element in pre-order:
    # [name, text, content].
    def element_access_rows(document)
      rows = []
      document.each_node do |node|
        next unless node.element?

        rows << [node.local_name, node.text, node.content]
      end
      rows
    end

    # PI targets and data, in document order.
    def processing_instructions(document)
      rows = []
      document.each_node do |node|
        rows << [node.name, node.data] if node.kind == :processing_instruction
      end
      rows
    end

    # Comment data, in document order.
    def comments(document)
      rows = []
      document.each_node { |node| rows << node.data if node.kind == :comment }
      rows
    end

    # Serialize the reference document as XML (indent: 0 canonical
    # facade shape: declaration if the source had one, escaped text,
    # self-closing empty elements).
    def to_xml(document)
      Writer.new(document).to_xml
    end

    # Serialize as HTML (void elements unclosed, raw script/style).
    def to_html(document)
      Writer.new(document).to_html
    end

    # Serialize as XHTML (void elements self-closed).
    def to_xhtml(document)
      Writer.new(document).to_xhtml
    end

    # EOL normalization per XML 1.0 §2.11.
    def normalize_eol(text)
      Normalizer.normalize_eol(text)
    end
  end
end
