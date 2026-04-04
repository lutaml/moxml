# frozen_string_literal: true

require "spec_helper"
require "benchmark/ips"
require "yaml"
require "fileutils"
require "time"

RSpec.describe "XPath Performance Benchmark", :performance do
  if ENV["SKIP_BENCHMARKS"]
    it "skips benchmarks when SKIP_BENCHMARKS is set" do
      skip "Benchmarks skipped. To run benchmarks, use: bundle exec rspec " \
           "spec/moxml/examples/xpath_benchmark_spec.rb or rake benchmark:xpath"
    end
  else
    let(:sample_xml) do
      <<~XML
        <?xml version="1.0"?>
        <library xmlns="http://example.org/library">
          <book id="1" category="fiction">
            <title>Book One</title>
            <author>Author A</author>
            <price>10.99</price>
          </book>
          <book id="2" category="non-fiction">
            <title>Book Two</title>
            <author>Author B</author>
            <price>15.99</price>
          </book>
          <book id="3" category="fiction">
            <title>Book Three</title>
            <author>Author A</author>
            <price>12.99</price>
          </book>
          <magazine id="4">
            <title>Magazine One</title>
            <publisher>Publisher X</publisher>
          </magazine>
          <magazine id="5">
            <title>Magazine Two</title>
            <publisher>Publisher Y</publisher>
          </magazine>
        </library>
      XML
    end

    let(:adapters) do
      %i[nokogiri libxml oga rexml ox headed_ox]
    end

    let(:xpath_patterns) do
      {
        "Simple descendant (//book)" => "//book",
        "Absolute path (/library/book)" => "/library/book",
        "Attribute predicate (//book[@id])" => "//book[@id]",
        "Wildcard (//*/title)" => "//*/title",
      }
    end

    describe "XPath query performance" do
      it "benchmarks XPath operations across all adapters" do
        xpath_patterns.each_value do |xpath|
          Benchmark.ips do |x|
            x.config(time: 5, warmup: 2)

            adapters.each do |adapter|
              x.report(adapter.to_s) do
                Moxml::Config.default_adapter = adapter
                doc = Moxml.new.parse(sample_xml)
                doc.xpath(xpath)
              rescue StandardError
                # Adapter doesn't support this pattern
                nil
              end
            end

            x.compare!
          end
        end
      end

      it "generates detailed performance comparison table" do
        results_table = {}

        xpath_patterns.each do |pattern_name, xpath|
          results_table[pattern_name] = {}

          adapters.each do |adapter|
            Moxml::Config.default_adapter = adapter
            doc = Moxml.new.parse(sample_xml)

            iterations = 0
            elapsed = Benchmark.realtime do
              1000.times do
                doc.xpath(xpath)
                iterations += 1
              end
            end

            ops_per_sec = iterations / elapsed
            results_table[pattern_name][adapter] = ops_per_sec
          rescue StandardError
            results_table[pattern_name][adapter] = nil
          end
        end

        adapters.each do |adapter|
          xpath_patterns.each_key do |pattern_name|
            ops = results_table[pattern_name][adapter]
            if ops

            end
          end
        end

        relative_results = {}
        xpath_patterns.each_key do |pattern_name|
          valid_results = results_table[pattern_name].compact
          next if valid_results.empty?

          fastest = valid_results.values.max
          relative_results[pattern_name] = {}
          results_table[pattern_name].each do |adapter, ops|
            if ops
              relative = ops / fastest
              relative_results[pattern_name][adapter] = relative

            else
              relative_results[pattern_name][adapter] = nil

            end
          end
        end

        # Save results to YAML
        output_dir = File.expand_path("../../../benchmarks", __dir__)
        FileUtils.mkdir_p(output_dir)
        output_file = File.join(output_dir, "xpath_performance.yml")

        yaml_data = {
          "metadata" => {
            "timestamp" => Time.now.utc.iso8601,
            "ruby_version" => RUBY_VERSION,
            "ruby_platform" => RUBY_PLATFORM,
          },
          "results" => {
            "absolute" => results_table.transform_values do |pattern_results|
              pattern_results.transform_values do |ops|
                ops ? ops.round(2) : "not_supported"
              end
            end,
            "relative" => relative_results.transform_values do |pattern_results|
              pattern_results.transform_values do |rel|
                rel ? rel.round(3) : "not_supported"
              end
            end,
          },
        }

        File.write(output_file, YAML.dump(yaml_data))
      end
    end

    describe "Namespace XPath performance" do
      let(:namespaced_xml) do
        <<~XML
          <?xml version="1.0"?>
          <lib:library xmlns:lib="http://example.org/library">
            <lib:book id="1">
              <lib:title>Book One</lib:title>
            </lib:book>
            <lib:book id="2">
              <lib:title>Book Two</lib:title>
            </lib:book>
          </lib:library>
        XML
      end

      let(:namespace_patterns) do
        {
          "Namespaced query (//ns:book)" =>
            ["//lib:book", { "lib" => "http://example.org/library" }],
          "Namespaced nested (//ns:book/ns:title)" =>
            ["//lib:book/lib:title", { "lib" => "http://example.org/library" }],
        }
      end

      it "benchmarks namespace-aware XPath" do
        namespace_capable_adapters = %i[nokogiri libxml oga]

        namespace_patterns.each_value do |(xpath, namespaces)|
          Benchmark.ips do |x|
            x.config(time: 5, warmup: 2)

            namespace_capable_adapters.each do |adapter|
              x.report(adapter.to_s) do
                Moxml::Config.default_adapter = adapter
                doc = Moxml.new.parse(namespaced_xml)
                doc.xpath(xpath, namespaces)
              rescue StandardError
                nil
              end
            end

            x.compare!
          end
        end
      end
    end
  end
end
