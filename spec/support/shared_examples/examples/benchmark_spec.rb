# frozen_string_literal: true

require "benchmark"
require "benchmark/ips"

RSpec.shared_examples "Performance Examples" do
  let(:context) { Moxml.new }

  let(:large_xml) do
    xml = "<root>\n"
    1000.times do |i|
      xml += "<item id='#{i}'><name>Test #{i}</name><value>#{i}</value></item>\n"
    end
    xml += "</root>"
    xml
  end

  it "measures parsing performance", focus: true do
    # pending "Run it on CI only" unless ENV['CI']

    doc = nil

    report = Benchmark.ips do |x|
      x.config(time: 5, warmup: 2)

      x.report("Parser") do
        doc = context.parse(large_xml)
      end

      x.report("Serializer") do
        _ = doc.to_xml
      end

      x.compare!
    end

    # first - parser, second - serializer
    thresholds = {
      nokogiri: [10, 10],
      oga: [10, 10],
      rexml: [10, 10],
      ox: [10, 10],
    }

    report.entries.each_with_index do |entry, index|
      puts "#{entry.label} performance: #{entry.ips.round(2)} ips"
      threshold = thresholds[context.config.adapter_name][index]
      expect(entry.ips).to be >= threshold,
                           "#{entry.label} performance below threshold: got #{entry.ips.round(2)} ips, expected >= #{threshold} ips"
    end
  end
end
