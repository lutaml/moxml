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

      # Absolute ips varies more than 2x across machines and even between
      # runs on the same machine (observed: rexml serializer 1.5-2.9 ips on
      # one machine). These thresholds sit at roughly half of typical
      # modern-runner throughput so they only trip on asymptotic
      # regressions (accidental O(n^2), broken caching), not on hardware
      # variance or a few percent of legitimate overhead.
      let(:thresholds) do
        {
          nokogiri: { parser: 8, serializer: 500 },
          oga: { parser: 5, serializer: 50 },
          rexml: { parser: 0, serializer: 1 },
          ox: { parser: 1, serializer: 400 },
          headed_ox: { parser: 1, serializer: 400 },
          libxml: { parser: 200, serializer: 30 },
          leptris: { parser: 1300, serializer: 900 },
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

        threshold = thresholds.dig(context.config.adapter_name,
                                   :serializer) || 1
        ips = report.entries.first.ips
        message = "Serializer performance below threshold: got #{ips.round(2)} ips, expected >= #{threshold} ips"
        expect(ips).to be >= threshold, message
      end
    end
  end
end
