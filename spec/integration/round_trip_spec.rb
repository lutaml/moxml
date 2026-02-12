# frozen_string_literal: true

require_relative "shared_examples/round_trip_testing"

RSpec.describe "Round-trip XML Testing" do
  let(:adapter_names) { Moxml::Adapter::AVALIABLE_ADAPTERS }

  def self.adapter_names
    Moxml::Adapter::AVALIABLE_ADAPTERS
  end

  def self.fixture_files
    return @fixture_files if defined?(@fixture_files)

    fixtures_dir = File.join(__dir__, "..", "fixtures", "round-trips")
    @fixture_files =
      Dir.glob(File.join(fixtures_dir, "niso-jats", "*.xml")).map do |file|
        relative_path = file.sub("#{fixtures_dir}/", "")
        {
          path: file,
          relative_path: relative_path,
          category: File.basename(File.dirname(file))
        }
      end
  end

  def load_fixture_content(file_path)
    File.read(file_path)
  end

  def normalize_xml(xml)
    # Normalize XML for comparison by removing whitespace differences
    xml.gsub(/>\s+</, "><")
       .gsub(/\s+/, " ")
       .gsub(" >", ">")
       .gsub("?> <", "?>\n<")
       .strip
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
      attributes: element.attributes.to_h,
      text: element.text&.strip,
      namespace: element.namespace&.href,
      children_count: element.children.size,
      xpath: element.xpath
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
