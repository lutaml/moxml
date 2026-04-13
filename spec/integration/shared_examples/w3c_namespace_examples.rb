# frozen_string_literal: true

RSpec.shared_examples "W3C namespace test: should parse" do |label, fixture_file, adapter, test_id|
  it label do
    skip "known #{adapter} limitation" if skip_for_adapter?(test_id, adapter)

    xml = File.binread(File.join(W3C_NS_FIXTURES_DIR, fixture_file))
    expect { moxml_context.parse(xml) }.not_to raise_error
  end
end
