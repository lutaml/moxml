# frozen_string_literal: true

require 'rspec'

# Helper methods for round-trip testing
def normalize_xml(xml)
  # Normalize XML for comparison by removing whitespace differences
  xml.gsub(/>\s+</, '><')           # Remove whitespace between tags
    .gsub("?>\s+", "?>")          # Clean XML declaration
    .gsub(/\s+>/, '>')            # Remove trailing spaces
    .strip
end

def semantically_equivalent?(xml1, xml2)
  # Simple semantic comparison focusing on content equivalence
  begin
    doc1 = Nokogiri::XML(xml1)
    doc2 = Nokogiri::XML(xml2)
    
    # Basic structure check
    return false unless doc1.root && doc2.root
    return false unless doc1.root.name == doc2.root.name
    
    # Attribute count check
    return false unless doc1.root.attributes.length == doc2.root.attributes.length
    
    # Element count check
    return false unless doc1.xpath("//*").length == doc2.xpath("//*").length
    
    # Text content check (normalized)
    text1 = doc1.xpath("//text()").map(&:text).join(" ").gsub(/\s+/, " ").strip
    text2 = doc2.xpath("//text()").map(&:text).join(" ").gsub(/\s+/, " ").strip
    return false unless text1 == text2
    
    # Generic element structure check
    elements1 = doc1.xpath("//*")
    elements2 = doc2.xpath("//*")
    
    # Compare element names and their attributes
    elements1.each_with_index do |elem1, i|
      elem2 = elements2[i]
      return false unless elem1.name == elem2.name
      
      # Compare attribute names and values
      attrs1 = elem1.attributes.sort.map { |name, attr| [name, attr.value] }
      attrs2 = elem2.attributes.sort.map { |name, attr| [name, attr.value] }
      return false unless attrs1 == attrs2
    end
    
    true
  rescue => e
    # If parsing fails, fall back to string comparison
    normalize_xml(xml1) == normalize_xml(xml2)
  end
end

def extract_elements_for_testing(doc)
  elements = {}
  
  # Extract root element
  elements[:root] = doc.root
  
  # Extract all elements with attributes (universal approach)
  begin
    elements_with_attrs = doc.xpath("//*[@*]")
  rescue Moxml::XPathError
    # Fallback for adapters that don't support @* syntax (like Ox)
    all_elements = doc.xpath("//*")
    elements_with_attrs = all_elements.select { |elem| elem.respond_to?(:attributes) && elem.attributes.any? }
  end
  if elements_with_attrs.any?
    elements[:elements_with_attributes] = elements_with_attrs.first(5)
    elements[:total_elements_with_attributes] = elements_with_attrs.length
  end
  
  # Extract text content (universal approach)
  text_nodes = doc.xpath("//text()").select { |node| node.text.strip != "" }
  if text_nodes.any?
    elements[:text_content] = text_nodes.first
    elements[:total_text_nodes] = text_nodes.length
  end
  
  # Extract all unique element names for universal testing
  all_elements = doc.xpath("//*")
  unique_element_names = all_elements.map(&:name).uniq
  elements[:unique_element_names] = unique_element_names
  elements[:total_elements] = all_elements.length
  
  # Extract first few elements of each type for testing
  # Prioritize elements with attributes to ensure consistency across adapters
  unique_element_names.each do |element_name|
    # First try to find elements with attributes (handle Ox adapter limitations)
    begin
      with_attrs = doc.xpath("//#{element_name}[@*]")
    rescue Moxml::XPathError
      # Fallback for adapters that don't support @* syntax (like Ox)
      # Find all elements and filter manually
      all_elements = doc.xpath("//#{element_name}")
      with_attrs = all_elements.select { |elem| elem.respond_to?(:attributes) && elem.attributes.any? }
    end
    
    # Then find elements without attributes (handle Ox adapter limitations)
    begin
      without_attrs = doc.xpath("//#{element_name}[not(@*)]")
    rescue Moxml::XPathError
      # Fallback for adapters that don't support not(@*) syntax (like Ox)
      all_elements = doc.xpath("//#{element_name}")
      without_attrs = all_elements.select { |elem| !elem.respond_to?(:attributes) || elem.attributes.empty? }
    end
    
    # Combine: elements with attributes first, then without attributes
    # Ensure we don't duplicate elements that might appear in both arrays
    # Convert both to proper arrays before combining to avoid NodeSet issues
    all_found = (with_attrs.to_a + without_attrs.to_a).uniq
    elements["#{element_name}_elements".to_sym] = all_found.first(3) if all_found.any?
  end
  
  elements
end

# Universal attribute conversion method for all adapters
def universal_attributes(element)
  return {} unless element&.respond_to?(:attributes)
  
  attrs = element.attributes
  
  # Handle different attribute formats across adapters
  if attrs.respond_to?(:map)
    # Nokogiri, Oga: array of Moxml::Attribute objects
    attrs.map { |attr| [attr.name, attr.value] }.to_h
  elsif attrs.respond_to?(:to_h)
    # Hash-like objects
    attrs.to_h
  elsif attrs.is_a?(Hash)
    # Direct hash
    attrs
  else
    # Ultimate fallback - try to convert to hash
    begin
      attrs.to_h
    rescue
      {}
    end
  end
end

def test_element_content(element)
  return nil unless element
  
  {
    name: element.name,
    attributes: universal_attributes(element),
    text: element.text.to_s.strip,
    namespace: element.namespace&.href,
    children_count: element.children.size,
    xpath: element.xpath("//*")
  }
end

RSpec.describe "Round-trip XML Testing" do
  # Explicit adapter names for clarity and maintainability
  let(:adapter_names) { [:nokogiri, :oga, :rexml, :ox] }

  def self.adapter_names
    [:nokogiri, :oga, :rexml, :ox]
  end

  def self.fixture_files
    return @fixture_files if defined?(@fixture_files)

    fixtures_dir = File.join(__dir__, "..", "fixtures", "round-trips")
    all_fixtures = Dir.glob(File.join(fixtures_dir, "**", "*.xml")).map do |file|
      relative_path = file.sub("#{fixtures_dir}/", "")
      {
        path: file,
        relative_path: relative_path,
        category: File.basename(File.dirname(file))
      }
    end
    @fixture_files = all_fixtures
  end

  def load_fixture_content(file_path)
    File.read(file_path)
  end

  describe "Round-trip testing between adapters" do
    fixture_files.each do |fixture|
      context "for fixture: #{fixture[:relative_path]}" do
        let(:fixture_content) { load_fixture_content(fixture[:path]) }
        
        adapter_names.each do |source_adapter|
          context "from #{source_adapter} adapter" do
            adapter_names.each do |target_adapter|
              next if source_adapter == target_adapter
              
              context "to #{target_adapter} adapter" do
                it "maintains XML structure and content" do
                  source_context = Moxml.new(source_adapter)
                  target_context = Moxml.new(target_adapter)
                  source_doc = source_context.parse(fixture_content)
                  target_doc = target_context.parse(source_doc.to_xml)
                  
                  # Extract elements for testing
                  source_elements = extract_elements_for_testing(source_doc)
                  target_elements = extract_elements_for_testing(target_doc)
                  
                  # Test universal elements that should exist in any XML
                  universal_keys = [:root, :elements_with_attributes, :text_content]
                  
                  # Add dynamic element keys based on actual XML structure (only element arrays)
                  source_elements.keys.each do |key|
                    if key.to_s.end_with?("_elements") && source_elements[key].is_a?(Array)
                      universal_keys << key
                    end
                  end
                  universal_keys.uniq!
                  
                  universal_keys.each do |key|
                    next unless source_elements[key] && target_elements[key]
                    
                    # For arrays, compare length and content
                    if source_elements[key].is_a?(Array) && target_elements[key].is_a?(Array)
                      expect(target_elements[key].length).to eq(source_elements[key].length), "Array length mismatch for #{key}"
                      source_elements[key].each_with_index do |source_item, i|
                        target_item = target_elements[key][i]
                        if source_item && target_item
                          source_content = test_element_content(source_item)
                          target_content = test_element_content(target_item)
                          expect(target_content[:name]).to eq(source_content[:name]), "Element name mismatch for #{key}[#{i}]"
                          expect(target_content[:attributes]).to eq(source_content[:attributes]), "Attributes mismatch for #{key}[#{i}]"
                        end
                      end
                    # For single elements, compare directly
                    elsif source_elements[key] && target_elements[key]
                      source_content = test_element_content(source_elements[key])
                      target_content = test_element_content(target_elements[key])
                      expect(target_content[:name]).to eq(source_content[:name]), "Element name mismatch for #{key}"
                      expect(target_content[:attributes]).to eq(source_content[:attributes]), "Attributes mismatch for #{key}"
                    end
                  end
                end

                it "produces equivalent XML after double round-trip" do
                  # Source -> Target -> Source
                  source_context = Moxml.new(source_adapter)
                  source_doc = source_context.parse(fixture_content)
                  
                  target_context = Moxml.new(target_adapter)
                  first_pass = target_context.parse(source_doc.to_xml)
                  
                  second_pass = source_context.parse(first_pass.to_xml)
                  
                  # Use semantic comparison instead of string equality
                  original_xml = source_doc.to_xml
                  final_xml = second_pass.to_xml
                  
                  expect(semantically_equivalent?(original_xml, final_xml)).to be(true),
                    "XML content should be semantically equivalent after double round-trip"
                  
                  # The structure should be equivalent (allowing for adapter differences)
                  expect(second_pass.root.name).to eq(source_doc.root.name)
                  
                  # Key content should be preserved
                  expect(second_pass.xpath("//*").size).to eq(source_doc.xpath("//*").size)
                end
              end
            end
          end
        end
      end
    end
  end
end
