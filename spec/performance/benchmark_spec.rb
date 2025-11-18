# frozen_string_literal: true

require "benchmark"
require "benchmark/ips"

RSpec.shared_examples "Performance Examples" do
  if ENV["SKIP_BENCHMARKS"]
    it "skips benchmarks when SKIP_BENCHMARKS is set" do
      skip "Benchmarks skipped. To run benchmarks, unset SKIP_BENCHMARKS"
    end
  else
    let(:context) { Moxml.new }

    let(:large_xml) do
      xml = "<root>\n"
      1000.times do |i|
        xml += "<item id='#{i}'><name>Test #{i}</name><value>#{i}</value></item>\n"
      end
      xml += "</root>"
      xml
    end

    context "measures performance" do
      let(:doc) { context.parse(large_xml) }

      let(:thresholds) do
        {
          nokogiri: { parser: 15, serializer: 1000 },
          oga: { parser: 10, serializer: 100 },
          rexml: { parser: 0, serializer: 60 },
          ox: { parser: 2, serializer: 1000 },
          headed_ox: { parser: 2, serializer: 1000 },
          libxml: { parser: 10, serializer: 30 },
        }
      end

      it "meets Parser performance threshold" do
        result = nil
        report = Benchmark.ips do |x|
          x.config(time: 5, warmup: 2)
          x.report("Parser") { result = context.parse(large_xml) }
        end

        threshold = thresholds.dig(context.config.adapter_name, :parser) || 1
        ips = report.entries.first.ips
        message = "Parser performance below threshold: got #{ips.round(2)} ips, expected >= #{threshold} ips"
        expect(ips).to be >= threshold, message
      end

      it "meets Serializer performance threshold" do
        report = Benchmark.ips do |x|
          x.config(time: 5, warmup: 2)
          x.report("Serializer") { _ = doc.to_xml }
        end

        threshold = thresholds.dig(context.config.adapter_name, :serializer) || 1
        ips = report.entries.first.ips
        message = "Serializer performance below threshold: got #{ips.round(2)} ips, expected >= #{threshold} ips"
        expect(ips).to be >= threshold, message
      end
    end
  end
end
