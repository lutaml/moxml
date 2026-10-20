# frozen_string_literal: true

require "spec_helper"
require "support/input_taxonomy"

# Executable-reference differential (TODO.sota/03): every adapter's
# answer for each taxonomy input is compared against the pure-Ruby
# reference implementation (Moxml::Reference), not against another
# adapter. Faces: document order, children listing, access truth
# table, attributes, PI/comment data, and serialization round-trip.
# Cells that differ cite a registered divergence (D-NN) or the
# adapter is fixed.
RSpec.describe "executable reference differential" do
  let(:references) { {} }

  def adapters
    Moxml::Adapter::AVAILABLE_ADAPTERS.uniq
  end

  def exempt?(input, face, adapter)
    InputTaxonomy::EXEMPT.dig(input.id, face, adapter)
  end

  def reference_for(input)
    references[input.id] ||= Moxml::Reference.parse(input.xml)
  end

  def adapter_document(name, xml)
    Moxml.new(name).parse(xml)
  rescue Moxml::Error, NotImplementedError, LoadError
    nil # unavailable in this environment
  end

  def elements(doc)
    doc.xpath("//*").to_a
  end

  def reference_elements(reference)
    rows = []
    reference.each_node { |node| rows << node if node.element? }
    rows
  end

  def pi_rows(doc)
    doc.traverse.filter_map do |node|
      [node.name, node.content] if node.node_type == :processing_instruction
    end
  end

  def comment_rows(doc)
    doc.traverse.filter_map do |node|
      node.content if node.node_type == :comment
    end
  end

  def compact(text)
    text.to_s.gsub(/\s+/, "")
  end

  it "answers document order and children listing like the reference" do
    InputTaxonomy.well_formed.each do |input|
      ref = reference_for(input)
      expected_order = Moxml::Reference.element_names(ref)
      expected_children = Moxml::Reference.child_element_names(ref)
      adapters.each do |name|
        doc = adapter_document(name, input.xml)
        next unless doc # unavailable
        next if exempt?(input, :nodes, name)

        got_order = elements(doc).map(&:name)
        expect(got_order).to eq(expected_order),
                             "#{input.id}/#{name}: document order differs " \
                             "from the reference: #{got_order.inspect} vs " \
                             "#{expected_order.inspect}"

        got_children = elements(doc).map do |element|
          element.children.grep(Moxml::Element).map(&:name)
        end
        expect(got_children).to eq(expected_children),
                                "#{input.id}/#{name}: children listing " \
                                "differs from the reference: " \
                                "#{got_children.inspect} vs " \
                                "#{expected_children.inspect}"
      end
    end
  end

  it "answers element text like the reference" do
    InputTaxonomy.well_formed.each do |input|
      expected = Moxml::Reference.element_access_rows(reference_for(input))
        .map { |(name, text, _content)| [name, text] }
      adapters.each do |name|
        doc = adapter_document(name, input.xml)
        next unless doc
        next if exempt?(input, :text, name)

        got = elements(doc).map { |element| [element.name, element.text] }
        expect(got).to eq(expected),
                       "#{input.id}/#{name}: text face differs from the " \
                       "reference: #{got.inspect} vs #{expected.inspect}"
      end
    end
  end

  it "answers attribute pairs like the reference" do
    InputTaxonomy.well_formed.each do |input|
      expected = reference_elements(reference_for(input)).map(&:attribute_pairs)
      adapters.each do |name|
        doc = adapter_document(name, input.xml)
        next unless doc

        got = elements(doc).map do |element|
          element.attribute_pairs.map { |(key, value)| [key, value] }
        end
        expect(got).to eq(expected),
                       "#{input.id}/#{name}: attribute face differs from " \
                       "the reference: #{got.inspect} vs #{expected.inspect}"
      end
    end
  end

  it "answers PI and comment data like the reference" do
    InputTaxonomy.well_formed.each do |input|
      ref = reference_for(input)
      expected_pis = Moxml::Reference.processing_instructions(ref)
      expected_comments = Moxml::Reference.comments(ref)
      adapters.each do |name|
        doc = adapter_document(name, input.xml)
        next unless doc

        got_pis = pi_rows(doc)
        expect(got_pis.map(&:first)).to eq(expected_pis.map(&:first)),
                                        "#{input.id}/#{name}: PI targets " \
                                        "differ from the reference"
        unless exempt?(input, :pi_content, name)
          expect(got_pis).to eq(expected_pis),
                             "#{input.id}/#{name}: PI data differs " \
                             "from the reference"
        end
        unless exempt?(input, :comment_content, name)
          expect(comment_rows(doc)).to eq(expected_comments),
                                       "#{input.id}/#{name}: comment data " \
                                       "differs from the reference"
        end
      end
    end
  end

  it "serializes to XML that re-parses to the reference information set" do
    InputTaxonomy.well_formed.each do |input|
      ref = reference_for(input)
      expected_order = Moxml::Reference.element_names(ref)
      expected_children = Moxml::Reference.child_element_names(ref)
      expected_text = Moxml::Reference.element_access_rows(ref)
        .map { |(name, text, _content)| [name, compact(text)] }
      adapters.each do |name|
        doc = adapter_document(name, input.xml)
        next unless doc
        next if exempt?(input, :serialize, name)

        begin
          serialized = doc.to_xml(indent: 0)
        rescue Moxml::Error, NotImplementedError, LoadError
          next # named engine limit, pinned by its own spec
        end
        reparsed = begin
          Moxml::Reference.parse(serialized)
        rescue Moxml::ParseError => e
          raise Moxml::ParseError,
                "#{input.id}/#{name}: serialized XML is not well-formed: " \
                "#{e.message}"
        end

        expect(Moxml::Reference.element_names(reparsed)).to eq(expected_order),
                                                            "#{input.id}/#{name}: serialized tree lost or reordered elements"
        expect(Moxml::Reference.child_element_names(reparsed)).to eq(expected_children),
                                                                  "#{input.id}/#{name}: serialized tree changed nesting"
        got_text = Moxml::Reference.element_access_rows(reparsed)
          .map { |(element, text, _content)| [element, compact(text)] }
        expect(got_text).to eq(expected_text),
                            "#{input.id}/#{name}: serialized tree changed " \
                            "text: #{got_text.inspect} vs #{expected_text.inspect}"
      end
    end
  end
end
