# frozen_string_literal: true
require_relative "shared_examples/round_trip_testing"

RSpec.describe "Round-trip XML Testing" do
  # Explicit adapter names for clarity and maintainability
  let(:adapter_names) { [:nokogiri, :oga, :rexml] }

  def self.adapter_names
    [:nokogiri, :oga, :rexml]
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
end
