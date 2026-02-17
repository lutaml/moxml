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
  elements_with_attrs = doc.xpath("//*[@*]")
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
    # First try to find elements with attributes
    with_attrs = doc.xpath("//#{element_name}[@*]")
    # Then find elements without attributes
    without_attrs = doc.xpath("//#{element_name}[not(@*)]")
    
    # Combine: elements with attributes first, then without attributes
    all_found = with_attrs + without_attrs
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

# Helper method to normalize whitespace for text comparison
def normalize_whitespace(text)
  return "" if text.nil? || text.empty?
  
  # Comprehensive space analysis before normalization
  puts "=== COMPREHENSIVE SPACE ANALYSIS ==="
  puts "Original text length: #{text.length}"
  
  # Analyze all whitespace characters
  whitespace_chars = text.chars.select { |c| c =~ /\s/ }
  puts "Total whitespace characters: #{whitespace_chars.length}"
  
  # Count different types of whitespace
  space_counts = {}
  whitespace_chars.each do |char|
    space_counts[char] = (space_counts[char] || 0) + 1
  end
  
  puts "Whitespace character breakdown:"
  space_counts.each do |char, count|
    puts "  '#{char}' (#{char.ord}): #{count} occurrences"
  end
  
  # Analyze consecutive space sequences
  space_sequences = text.scan(/\s+/)
  puts "Consecutive space sequences:"
  space_sequences.each_with_index do |seq, i|
    puts "  Sequence #{i + 1}: '#{seq}' (length: #{seq.length}, bytes: #{seq.bytes.map { |b| b.to_s(16).rjust(2, '0') }.join(' ')})"
  end
  
  # Find all space sequences longer than 1
  long_spaces = space_sequences.select { |seq| seq.length > 1 }
  puts "Long space sequences (>1 char): #{long_spaces.length}"
  long_spaces.each_with_index do |seq, i|
    puts "  Long space #{i + 1}: '#{seq}' (length: #{seq.length})"
  end
  
  # Analyze positions of spaces
  space_positions = []
  text.chars.each_with_index do |char, i|
    space_positions << i if char =~ /\s/
  end
  puts "Space positions (first 20): #{space_positions[0, 20].join(', ')}#{'...' if space_positions.length > 20}"
  puts "Space positions (last 20): #{space_positions[-20, 20].join(', ')}#{'...' if space_positions.length > 20}"
  
  puts "=== END SPACE ANALYSIS ==="
  
  # New normalization pattern: replace all kinds of space characters with one space
  normalized = text.gsub(/\s+/, ' ').strip
  
  # Comprehensive debugging for all differences
  puts "=== COMPREHENSIVE NORMALIZATION DEBUG ==="
  puts "Input text length: #{text.length}"
  puts "Input text (first 100 chars): '#{text[0, 100]}#{'...' if text.length > 100}'"
  puts "Input text (last 100 chars): '#{text[-100, 100]}#{'...' if text.length > 100}'"
  puts "Input text bytes: #{text.bytes.map { |b| b.to_s(16).rjust(2, '0') }.join(' ')}"
  puts "Output text length: #{normalized.length}"
  puts "Output text (first 100 chars): '#{normalized[0, 100]}#{'...' if normalized.length > 100}'"
  puts "Output text (last 100 chars): '#{normalized[-100, 100]}#{'...' if normalized.length > 100}'"
  puts "Output text bytes: #{normalized.bytes.map { |b| b.to_s(16).rjust(2, '0') }.join(' ')}"
  puts "=== END COMPREHENSIVE DEBUG ==="
  
  normalized
end

RSpec.shared_examples "cross adapter round trip testing" do |fixture_path, source_adapter, target_adapter|
  let(:fixture_content) { File.read(fixture_path) }
  let(:original_normalized) { normalize_xml(fixture_content) }
  let(:source_doc) do
    context = Moxml.new(source_adapter)
    context.parse(fixture_content)
  end

  it "maintains XML structure and content" do
    # Parse with source adapter
    source_xml = source_doc.to_xml
    
    # Re-parse with target adapter
    target_context = Moxml.new(target_adapter)
    target_doc = target_context.parse(source_xml)
    
    # Basic structure checks
    expect(target_doc.root.name).to eq(source_doc.root.name)
    
    # Check that key elements are preserved using universal approach
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
        
        # Normalize whitespace for comparison to handle adapter differences
        puts "=== COMPARISON DEBUG FOR #{key} ==="
        puts "Source text length: #{source_content[:text].length}"
        puts "Source text (first 100 chars): '#{source_content[:text][0, 100]}#{'...' if source_content[:text].length > 100}'"
        puts "Target text length: #{target_content[:text].length}"
        puts "Target text (first 100 chars): '#{target_content[:text][0, 100]}#{'...' if target_content[:text].length > 100}'"
        
        normalized_source_text = normalize_whitespace(source_content[:text])
        normalized_target_text = normalize_whitespace(target_content[:text])
        
        puts "Normalized source length: #{normalized_source_text.length}"
        puts "Normalized target length: #{normalized_target_text.length}"
        puts "Are they equal? #{normalized_source_text == normalized_target_text}"
        
        if normalized_source_text != normalized_target_text
          puts "=== COMPREHENSIVE DIFFERENCE ANALYSIS ==="
          puts "Source length: #{normalized_source_text.length}"
          puts "Target length: #{normalized_target_text.length}"
          
          shorter = [normalized_source_text, normalized_target_text].min_by(&:length)
          longer = [normalized_source_text, normalized_target_text].max_by(&:length)
          
          differences = []
          shorter.chars.each_with_index do |char, i|
            if longer[i] != char
              differences << {
                position: i,
                expected: char,
                expected_ord: char.ord,
                got: longer[i] || 'EOF',
                got_ord: (longer[i] || 'EOF').ord
              }
            end
          end
          
          # Handle case where longer text has extra characters
          if longer.length > shorter.length
            (shorter.length..longer.length - 1).each do |i|
              differences << {
                position: i,
                expected: 'EOF',
                expected_ord: 'EOF',
                got: longer[i] || 'EOF',
                got_ord: (longer[i] || 'EOF').ord
              }
            end
          end
          
          # Find first difference dynamically
          first_diff = differences.first
          first_diff_pos = first_diff ? first_diff[:position] : -1
          
          puts "Found #{differences.length} differences:"
          puts "First difference at position: #{first_diff_pos}"
          
          # Show context around the first failing character
          if first_diff_pos >= 0
            context_start = [first_diff_pos - 20, 0].max
            context_end = [first_diff_pos + 20, longer.length - 1].min
            
            puts "Context around first difference (#{context_start}-#{context_end}):"
            puts "  Expected: '#{shorter[context_start..context_end]}'"
            puts "  Got:      '#{longer[context_start..context_end]}'"
            
            # Show byte-level context for first difference
            puts "Byte context around first difference:"
            shorter_bytes = shorter.bytes[context_start..context_end]
            longer_bytes = longer.bytes[context_start..context_end]
            puts "  Expected bytes: #{shorter_bytes.map { |b| b.to_s(16).rjust(2, '0') }.join(' ')}"
            puts "  Got bytes:      #{longer_bytes.map { |b| b.to_s(16).rjust(2, '0') }.join(' ')}"
            
            # Show character-by-character analysis around first difference
            puts "Character analysis around first difference:"
            (context_start..context_end).each do |i|
              exp_char = shorter[i] || 'EOF'
              got_char = longer[i] || 'EOF'
              exp_is_space = exp_char =~ /\s/
              got_is_space = got_char =~ /\s/
              marker = (i == first_diff_pos) ? '>>> FIRST DIFF <<<' : ''
              puts "  Pos #{i}: Expected '#{exp_char}' (#{exp_char.ord}) #{'WHITESPACE' if exp_is_space} | Got '#{got_char}' (#{got_char.ord}) #{'WHITESPACE' if got_is_space} #{marker}"
            end
          end
          
          # Show all differences (limited to first 10 to avoid too much output)
          puts "=== ALL DIFFERENCES (first 10 of #{differences.length}) ==="
          differences[0, 10].each_with_index do |diff, index|
            puts "  Difference #{index + 1}:"
            puts "    Position: #{diff[:position]}"
            puts "    Expected: '#{diff[:expected]}' (#{diff[:expected_ord]})"
            puts "    Got: '#{diff[:got]}' (#{diff[:got_ord]})"
            
            # Show 5 characters before and after each difference
            start_pos = [diff[:position] - 5, 0].max
            end_pos = [diff[:position] + 5, longer.length - 1].min
            
            puts "    Context (#{start_pos}-#{end_pos}):"
            puts "      Expected: '#{shorter[start_pos..end_pos]}'"
            puts "      Got:      '#{longer[start_pos..end_pos]}'"
            puts
          end
          
          # Summary of difference types
          newline_diffs = differences.select { |d| d[:got] == "\n" || d[:expected] == "\n" }
          space_diffs = differences.select { |d| d[:got] == " " || d[:expected] == " " }
          other_diffs = differences - newline_diffs - space_diffs
          
          puts "=== DIFFERENCE SUMMARY ==="
          puts "Total differences: #{differences.length}"
          puts "Newline differences: #{newline_diffs.length}"
          puts "Space differences: #{space_diffs.length}"
          puts "Other character differences: #{other_diffs.length}"
          
          if newline_diffs.any?
            puts "Newline positions: #{newline_diffs.map { |d| d[:position] }.join(', ')}"
          end
          if space_diffs.any?
            puts "Space positions: #{space_diffs.map { |d| d[:position] }.join(', ')}"
          end
          if other_diffs.any?
            puts "Other positions: #{other_diffs.map { |d| d[:position] }.join(', ')}"
          end
          
          puts "=== END COMPREHENSIVE DIFFERENCE ANALYSIS ==="
        end
        
        expect(normalized_target_text).to eq(normalized_source_text)
      end
    end
  end

  it "produces equivalent XML after double round-trip" do
    # Source -> Target -> Source
    target_context = Moxml.new(target_adapter)
    first_pass = target_context.parse(source_doc.to_xml)
    
    source_context = Moxml.new(source_adapter)
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
