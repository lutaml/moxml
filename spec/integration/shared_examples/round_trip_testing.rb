# frozen_string_literal: true

RSpec.shared_examples "round trip XML parsing" do |fixture_path, adapter_name|
  let(:fixture_content) { File.read(fixture_path) }
  let(:fixture_name) { File.basename(fixture_path, ".xml") }
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

RSpec.shared_examples "cross adapter round trip testing" do |fixture_path, source_adapter, target_adapter|
  let(:fixture_content) { File.read(fixture_path) }
  let(:original_normalized) { normalize_xml(fixture_content) }
  let(:source_doc) do
    Moxml.with_config(source_adapter) do
      Moxml.new.parse(fixture_content)
    end
  end

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


RSpec.shared_examples "namespace handling validation" do |fixture_path, adapter_name|
  let(:fixture_content) { File.read(fixture_path) }
  
  it "handles namespaces correctly across adapters" do
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
