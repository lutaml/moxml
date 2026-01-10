# frozen_string_literal: true

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
        let(:fixture_content) { load_fixture_content(fixture[:path]) }
        
        adapter_names.each do |adapter_name|
          context "with #{adapter_name} adapter" do
            let(:parsed_doc) do
              Moxml.with_config(adapter_name) do
                Moxml.new.parse(fixture_content)
              end
            end

            it "successfully parses the XML document" do
              expect(parsed_doc).to be_a(Moxml::Document)
              expect(parsed_doc.root).not_to be_nil
            end

            it "extracts and tests element content" do
              elements = extract_elements_for_testing(parsed_doc)
              
              elements.each do |element_type, element|
                next unless element
                
                content = test_element_content(element)
                
                expect(content[:name]).to be_a(String)
                expect(content[:name]).not_to be_empty if content[:name]
                
                expect(content[:attributes]).to be_a(Hash)
                
                if content[:text] && !content[:text].empty?
                  expect(content[:text]).to be_a(String)
                end
                
                expect(content[:children_count]).to be_a(Integer)
                expect(content[:children_count]).to be >= 0
              end
            end

            it "can query specific elements by XPath" do
              # Test basic XPath queries
              expect(parsed_doc.xpath("//*")).not_to be_empty
              
              # Test root element access
              root_xpath = "/#{parsed_doc.root.name}"
              root_by_xpath = parsed_doc.xpath(root_xpath)
              expect(root_by_xpath).not_to be_empty
              expect(root_by_xpath.first.name).to eq(parsed_doc.root.name)
            end

            it "preserves document structure" do
              # Test that the document can be serialized back
              serialized = parsed_doc.to_xml
              expect(serialized).not_to be_empty
              
              # Test that we can parse the serialized version
              reparsed = Moxml.with_config(adapter_name) { Moxml.new.parse(serialized) }
              expect(reparsed.root.name).to eq(parsed_doc.root.name)
            end
          end
        end
      end
    end
  end

  describe "Round-trip testing between adapters" do
    fixture_files.each do |fixture|
      context "for fixture: #{fixture[:relative_path]}" do
        let(:fixture_content) { load_fixture_content(fixture[:path]) }
        let(:original_normalized) { normalize_xml(fixture_content) }
        
        adapter_names.each do |source_adapter|
          context "from #{source_adapter} adapter" do
            let(:source_doc) do
              Moxml.with_config(source_adapter) do
                Moxml.new.parse(fixture_content)
              end
            end

            adapter_names.each do |target_adapter|
              next if source_adapter == target_adapter
              
              context "to #{target_adapter} adapter" do
                it "maintains XML structure and content" do
                  # Parse with source adapter
                  source_xml = source_doc.to_xml
                  
                  # Re-parse with target adapter
                  target_doc = Moxml.with_config(target_adapter) do
                    Moxml.new.parse(source_xml)
                  end
                  
                  # Basic structure checks
                  expect(target_doc.root.name).to eq(source_doc.root.name)
                  
                  # Check that key elements are preserved
                  source_elements = extract_elements_for_testing(source_doc)
                  target_elements = extract_elements_for_testing(target_doc)
                  
                  source_elements.keys.each do |key|
                    next unless source_elements[key] && target_elements[key]
                    
                    source_content = test_element_content(source_elements[key])
                    target_content = test_element_content(target_elements[key])
                    
                    expect(target_content[:name]).to eq(source_content[:name])
                    expect(target_content[:attributes]).to eq(source_content[:attributes])
                    expect(target_content[:text]).to eq(source_content[:text])
                  end
                end

                it "produces equivalent XML after double round-trip" do
                  # Source -> Target -> Source
                  first_pass = Moxml.with_config(target_adapter) do
                    Moxml.new.parse(source_doc.to_xml)
                  end
                  
                  second_pass = Moxml.with_config(source_adapter) do
                    Moxml.new.parse(first_pass.to_xml)
                  end
                  
                  # Normalize both for comparison
                  original_normalized = normalize_xml(source_doc.to_xml)
                  final_normalized = normalize_xml(second_pass.to_xml)
                  expect(original_normalized).to eq(final_normalized)
                  
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

  describe "Full round-trip through all adapters" do
    fixture_files.each do |fixture|
      context "for fixture: #{fixture[:relative_path]}" do
        let(:fixture_content) { load_fixture_content(fixture[:path]) }
        
        it "maintains consistency through all adapters" do
          current_xml = fixture_content
          adapter_sequence = []
          
          # Pass through each adapter in sequence
          adapter_names.each do |adapter_name|
            adapter_sequence << adapter_name
            
            doc = Moxml.with_config(adapter_name) do
              Moxml.new.parse(current_xml)
            end
            
            # Test that we can extract basic information
            expect(doc&.root).not_to be_nil
            expect(doc.root.name).not_to be_empty
            
            # Update for next iteration
            current_xml = doc.to_xml
          end
          
          # Final document should still be valid XML
          final_doc = Moxml.with_config(adapter_names.first) do
            Moxml.new.parse(current_xml)
          end
          
          expect(final_doc.root.name).not_to be_empty
          
          # The number of elements should be preserved (approximately)
          original_doc = Moxml.with_config(adapter_names.first) { Moxml.new.parse(fixture_content) }
          expect(final_doc.xpath("//*").size).to eq(original_doc.xpath("//*").size)
        end
      end
    end
  end

  describe "Adapter-specific behavior validation" do
    fixture_files.select { |f| f[:category] == "metanorma" }.first(3).each do |fixture|
      context "for metanorma fixture: #{File.basename(fixture[:path])}" do
        let(:fixture_content) { load_fixture_content(fixture[:path]) }
        
        it "handles namespaces correctly across adapters" do
          adapter_names.each do |adapter_name|
            doc = Moxml.with_config(adapter_name) { Moxml.new.parse(fixture_content) }
            
            # Check namespace handling
            if doc.root.namespace
              expect(doc.root.namespace.href).not_to be_empty
            end
            
            # Check for namespace declarations
            namespaces = doc.root.namespaces
            expect(namespaces).to respond_to(:each)
          end
        end
      end
    end
  end
end
