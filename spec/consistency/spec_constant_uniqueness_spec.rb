# frozen_string_literal: true

require "spec_helper"

# Checker integrity (TODO.model/06): top-level constant names in spec
# files all resolve through Object inside example blocks, so the same
# name defined by two files makes the last-loaded file win — the 0.5.143
# CORPUS collision made the battery fail ~50% of runs with a foreign
# corpus. This guard kills the class.
RSpec.describe "spec-file top-level constant uniqueness" do
  it "defines each constant name in at most one spec/support file" do
    seen = {}

    Dir["spec/**/*.rb"].each do |path|
      File.readlines(path).each_with_index do |line, i|
        match = line.match(/\A\s*([A-Z][A-Z0-9_]*)\s*=[^=]/)
        next unless match

        name = match[1]
        expect(seen)
          .not_to have_key(name),
                  "#{name} defined at #{seen[name]} and #{path}:#{i + 1} " \
                  "— constants inside example blocks collide through " \
                  "Object; give one file a unique name"
        seen[name] = "#{path}:#{i + 1}"
      end
    end
  end
end
