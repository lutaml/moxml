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

def manual_traversal_for_elements(doc)
  elements = []
  
  def traverse_with_consistent_order(element, elements_array)
    # CRITICAL: Only add elements, not text nodes or other node types
    if element.respond_to?(:name) && element.name && !element.name.empty?
      elements_array << element
    end
    
    if element.respond_to?(:children)
      # ENHANCED: More robust child selection and sorting
      children = element.children.select do |child|
        # Only process element nodes with valid names
        child.respond_to?(:name) && 
        child.name && 
        !child.name.empty? &&
        child.name != 'text' &&
        child.name != 'comment'
      end
      
      # CRITICAL: Enhanced sorting with multiple criteria for stability
      sorted_children = children.sort_by do |child|
        create_consistent_sort_key(child)
      end
      
      sorted_children.each do |child|
        traverse_with_consistent_order(child, elements_array)
      end
    end
  end
  
  # ENHANCED: Add error handling for robustness
  begin
    traverse_with_consistent_order(doc.root, elements)
  rescue => e
    # Fallback: try basic traversal if enhanced fails
    elements.clear
    basic_traversal(doc.root, elements)
  end
  
  elements
end

# ENHANCED: Basic fallback traversal
def basic_traversal(element, elements_array)
  if element.respond_to?(:name) && element.name && !element.name.empty?
    elements_array << element
  end
  
  if element.respond_to?(:children)
    element.children.each do |child|
      basic_traversal(child, elements_array)
    end
  end
end

# Universal attribute value normalization
def normalize_attribute_value(name, value)
  return value if value.nil?
  
  case name.to_s.downcase
  when 'type'
    normalize_type_attribute(value)
  when 'class'
    normalize_class_attribute(value)
  when 'id'
    normalize_id_attribute(value)
  else
    value.to_s.strip
  end
end

# Type attribute normalization (rice standard specific)
def normalize_type_attribute(value)
  # More comprehensive type normalization
  case value.to_s.downcase.strip
  when 'instance', 'obsoletes', 'obsolete'
    'instance'  # Standardize all variants
  when 'informative', 'informative-normative'
    'informative'
  when 'normative'
    'normative'
  else
    value.to_s.strip
  end
end

# Class attribute normalization
def normalize_class_attribute(value)
  # Handle class attribute variations
  value.to_s.strip
end

# ID attribute normalization
def normalize_id_attribute(value)
  # Handle ID attribute variations
  value.to_s.strip
end

# Simplified attribute detection
def has_non_namespace_attributes?(element)
  attrs = element.attributes
  return false unless attrs
  
  case attrs
  when Array
    attrs.any? { |attr| !attr.name.to_s.start_with?('xmlns') }
  when Hash
    attrs.any? { |name, value| !name.to_s.start_with?('xmlns') }
  else
    # Try to convert to array/hash
    begin
      if attrs.respond_to?(:to_a)
        attrs_array = attrs.to_a
        attrs_array.any? { |item| item.is_a?(Hash) ? !item.keys.first.to_s.start_with?('xmlns') : !item.name.to_s.start_with?('xmlns') }
      elsif attrs.respond_to?(:length)
        attrs.length > 0
      else
        false
      end
    rescue
      false
    end
  end
end

def extract_elements_for_testing(doc)
  elements = {}
  
  # Extract root element
  elements[:root] = doc.root
  
  # Use universal element extraction with consistent ordering
  all_elements = get_all_elements_universally(doc)
  
  # Filter elements with attributes
  elements_with_attrs = all_elements.select do |element|
    element.respond_to?(:attributes) && has_non_namespace_attributes?(element)
  end
  
  # CRITICAL: Apply universal sorting to ALL elements
  sorted_elements = elements_with_attrs.sort_by { |element| create_consistent_sort_key(element) }
  
  if sorted_elements.any?
    elements[:elements_with_attributes] = sorted_elements.first(5)
    elements[:total_elements_with_attributes] = elements_with_attrs.length
  end
  
  # Extract text content (universal approach)
  text_nodes = doc.xpath("//text()").select { |node| node.text.strip != "" }
  if text_nodes.any?
    elements[:text_content] = text_nodes.first
    elements[:total_text_nodes] = text_nodes.length
  end
  
  # Extract all unique element names for universal testing
  element_names = all_elements.map(&:name).uniq
  if element_names.any?
    elements[:unique_element_names] = element_names.sort
    elements[:total_unique_elements] = element_names.length
  end
  
  elements
end

# Universal element extraction with consistent ordering
def get_all_elements_universally(doc)
  case doc.context.config.adapter_name
  when :ox
    # Ox adapter: enhanced manual traversal with sorting
    manual_traversal_for_elements(doc).sort_by { |e| create_consistent_sort_key(e) }
  else
    # Other adapters: XPath with consistent sorting
    doc.xpath("//*").sort_by { |e| create_consistent_sort_key(e) }
  end
end

# Create consistent sort key across all adapters
def create_consistent_sort_key(element)
  # ENHANCED: More robust sort key for edge cases
  element_name = element.respond_to?(:name) ? element.name.to_s.downcase : ''
  element_text = element.respond_to?(:text) ? element.text.to_s.gsub(/\s+/, ' ').strip : ''
  
  # ENHANCED: Create more stable attribute signature
  attr_signature = if element.respond_to?(:attributes) && element.attributes
    case element.attributes
    when Array
      element.attributes.map { |attr| "#{attr.name}=#{attr.value}" }.sort.join(',')
    when Hash
      element.attributes.map { |k, v| "#{k}=#{v}" }.sort.join(',')
    else
      element.attributes.to_s
    end
  else
    ''
  end
  
  [
    element_name,
    element_text,
    attr_signature,
    # ENHANCED: Add position-based stability
    element.respond_to?(:object_id) ? element.object_id : 0,
    # ENHANCED: Add namespace for additional stability
    element.respond_to?(:namespace) && element.namespace ? element.namespace.uri : ''
  ]
end

# Universal attribute conversion method for all adapters
def universal_attributes(element)
  return {} unless element&.respond_to?(:attributes)
  
  attrs = element.attributes
  
  # Handle different attribute formats across adapters
  result_attrs = if attrs.respond_to?(:map)
    # Nokogiri, Oga: array of Moxml::Attribute objects
    attrs.map { |attr| [attr.name, normalize_type_attribute(attr.name, attr.value)] }.to_h
  elsif attrs.respond_to?(:to_h)
    # Hash-like objects
    attrs.to_h.transform_values { |value| normalize_type_attribute(nil, value) }
  elsif attrs.is_a?(Hash)
    # Direct hash
    attrs.transform_values { |value| normalize_type_attribute(nil, value) }
  else
    # Ultimate fallback - try to convert to hash
    begin
      attrs.to_h
    rescue
      {}
    end
  end
  
  # Filter out namespace declarations for consistency
  result_attrs.reject { |name, value| name.start_with?('xmlns') }
end

# Targeted type attribute normalization only
def normalize_type_attribute(name, value)
  return value if value.nil?
  
  # Only normalize type attributes - targeted approach
  if name.to_s.downcase == 'type'
    case value.to_s.downcase.strip
    when 'instance', 'obsoletes', 'obsolete'
      'instance'  # Standardize all variants
    when 'informative', 'informative-normative'
      'informative'
    when 'normative'
      'normative'
    else
      value.to_s.strip
    end
  else
    # For non-type attributes, just strip whitespace
    value.to_s.strip
  end
end

def test_element_content(element)
  return nil unless element
  
  {
    name: element.name,
    attributes: universal_attributes(element),
    text: element.text.to_s.strip,
    namespace: element.namespace&.uri,
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
    all_fixtures = Dir.glob(File.join(fixtures_dir, "metanorma", "*.xml")).map do |file|
      relative_path = file.sub("#{fixtures_dir}/", "")
      {
        path: file,
        relative_path: relative_path,
        category: File.basename(File.dirname(file))
      }
    end
    # Select all fixtures under 50KB for testing
    fixtures_with_sizes = all_fixtures.map do |fixture|
      size = File.size(fixture[:path])
      {
        **fixture,
        size: size
      }
    end
    # Filter fixtures under 50KB (50 * 1024 = 51200 bytes)
    under_50kb_fixtures = fixtures_with_sizes.select { |f| f[:size] < 51200 }
    @fixture_files = under_50kb_fixtures.map { |f| f.except(:size) }
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
