RSpec.describe "Test all shared examples" do
  all_shared_examples = [
    'Moxml::Node',
    'Moxml::Namespace',
    'Moxml::Attribute',
    'Moxml::NodeSet',
    'Moxml::Element',
  ]

  Moxml::Adapter::AVALIABLE_ADAPTERS.each do |adapter_name|
  # [:nokogiri].each do |adapter_name|
  # [:oga].each do |adapter_name|
    context "with #{adapter_name}" do
      before(:all) do
        Moxml.configure do |config|
          config.adapter = adapter_name
        end
      end

      all_shared_examples.each do |shared_example_name|
        it_behaves_like shared_example_name
      end
    end
  end
end
