# frozen_string_literal: true

require_relative "shared_examples/round_trip_testing"

RSpec.describe "Round-trip XML Testing" do
  let(:adapter_names) { [Moxml::Adapter::AVALIABLE_ADAPTERS[0], Moxml::Adapter::AVALIABLE_ADAPTERS[1], Moxml::Adapter::AVALIABLE_ADAPTERS[3]] }

  def self.adapter_names
    [Moxml::Adapter::AVALIABLE_ADAPTERS[0], Moxml::Adapter::AVALIABLE_ADAPTERS[1], Moxml::Adapter::AVALIABLE_ADAPTERS[3]]
  end

  def self.fixture_files
    return @fixture_files if defined?(@fixture_files)

    fixtures_dir = File.join(__dir__, "..", "fixtures", "round-trips")
    all_fixtures = Dir.glob(File.join(fixtures_dir, "niso-jats", "*.xml")).map do |file|
      relative_path = file.sub("#{fixtures_dir}/", "")
      {
        path: file,
        relative_path: relative_path,
        category: File.basename(File.dirname(file))
      }
    end
    @fixture_files = all_fixtures.first(1)
  end

  def load_fixture_content(file_path)
    File.read(file_path)
  end

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
    
    # Extract common element types if they exist
    %w[title author name organization child element section].each do |tag_name|
      found = doc.xpath("//#{tag_name}")
      elements[tag_name.to_sym] = found.first if found.any?
    end
    
    # Extract elements with attributes
    doc.xpath("//*[@*]").first(3).each_with_index do |el, i|
      elements["with_attrs_#{i}".to_sym] = el
    end
    
    # Extract text content
    text_nodes = doc.xpath("//text()").select { |node| node.text.strip != "" }
    elements[:text_content] = text_nodes.first if text_nodes.any?
    
    elements
  end

  def test_element_content(element)
    return nil unless element
    
    {
      name: element.name,
      attributes: element.attributes.map { |attr| [attr.name, attr.value] }.to_h,
      text: element.text.to_s.strip,
      namespace: element.namespace&.href,
      children_count: element.children.size,
      xpath: element.xpath("//*")
    }
  end

  describe "Fixture file parsing and content extraction" do
    fixture_files.each do |fixture|
      context "for fixture: #{fixture[:relative_path]}" do
        adapter_names.each do |adapter_name|
          context "with #{adapter_name} adapter" do
            it_behaves_like "round trip XML parsing", fixture[:path], adapter_name
          end
        end
      end
    end
  end

  describe "Round-trip testing between adapters" do
    fixture_files.each do |fixture|
      context "for fixture: #{fixture[:relative_path]}" do
        adapter_names.each do |source_adapter|
          context "from #{source_adapter} adapter" do
            adapter_names.each do |target_adapter|
              next if source_adapter == target_adapter
              
              context "to #{target_adapter} adapter" do
                it_behaves_like "cross adapter round trip testing", fixture[:path], source_adapter, target_adapter
              end
            end
          end
        end
      end
    end
  end

  describe "Adapter-specific behavior validation" do
    fixture_files.select { |f| f[:category] == "metanorma" }.first(3).each do |fixture|
      context "for metanorma fixture: #{File.basename(fixture[:path])}" do
        adapter_names.each do |adapter_name|
          context "with #{adapter_name} adapter" do
            it_behaves_like "namespace handling validation", fixture[:path], adapter_name
          end
        end
      end
    end
  end
end
