# frozen_string_literal: true

require "rexml/document"

W3C_NS_FIXTURES_DIR = File.expand_path("../fixtures/w3c/namespaces/1.0", __dir__)

# Parse the test catalog to get test metadata
def load_w3c_namespace_tests
  catalog = File.read(File.join(W3C_NS_FIXTURES_DIR, "rmt-ns10.xml"))
  doc = REXML::Document.new(catalog)
  tests = []
  doc.elements.each("TESTCASES/TEST") do |test_el|
    tests << {
      id: test_el.attributes["ID"],
      uri: test_el.attributes["URI"],
      type: test_el.attributes["TYPE"],
      sections: test_el.attributes["SECTIONS"],
      description: test_el.text.strip,
    }
  end
  tests
end

W3C_NAMESPACE_TESTS = load_w3c_namespace_tests

# Known adapter-level limitations for specific tests.
# These are parser bugs/limitations, not moxml issues.
ADAPTER_SKIP_TESTS = {
  # Test 006: ISO-8859-1 encoded IRI — adapters receive binary-read content
  # and may fail on encoding before namespace processing begins.
  "rmt-ns10-006" => :all,
  # Test 047: DOCTYPE with colon in element name — Oga parser limitation.
  "ht-ns10-047" => [:oga],
}.freeze

def skip_for_adapter?(test_id, adapter)
  skip_config = ADAPTER_SKIP_TESTS[test_id]
  return false unless skip_config

  skip_config == :all || skip_config.include?(adapter)
end
