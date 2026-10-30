# frozen_string_literal: true

# Processing model §Entities (normative): pinned here.

require "spec_helper"

# The entity-registry conformance dataset (#496): lookup and
# restoration answers AS DATA, pinned by the Ruby suite and exported
# for the Rust/TS runners. A row failing here breaks the
# cross-language contract. Rows seed a fresh :custom registry through
# the public provider path — seed values are lexical forms — then pin
# every face answer for one name and one codepoint query.
RSpec.describe "entity-registry conformance dataset" do
  it "carries the dataset" do
    expect(Moxml::EntityRegistry::ENTITY_CONFORMANCE_CASES.size).to be >= 10
  end

  it "answers every row exactly as the dataset expects" do
    Moxml::EntityRegistry::ENTITY_CONFORMANCE_CASES.each do |row|
      seed, qname, qcp, restore_entities, restoration_mode, declared,
        codepoint, names, primary, standard, restore = row
      registry = Moxml::EntityRegistry.new(
        mode: :custom,
        entity_provider: -> { seed },
      )

      label = "seed #{seed.inspect}, qname #{qname.inspect}, qcp #{qcp}"

      expect(registry.declared?(qname)).to eql(declared),
                                           "declared?(#{qname.inspect}) [#{label}]"
      expect(registry.codepoint_for_name(qname)).to eql(codepoint),
                                                    "codepoint_for_name(" \
                                                    "#{qname.inspect}) " \
                                                    "[#{label}]"
      expect(registry.names_for_codepoint(qcp)).to eql(names),
                                                   "names_for_codepoint(" \
                                                   "#{qcp}) [#{label}]"
      expect(registry.primary_name_for_codepoint(qcp)).to eql(primary),
                                                          "primary_name_" \
                                                          "for_codepoint(" \
                                                          "#{qcp}) [#{label}]"
      expect(registry.standard_entity?(qcp)).to eql(standard),
                                                "standard_entity?(#{qcp}) " \
                                                "[#{label}]"
      config = Moxml::Config.new
      config.restore_entities = restore_entities
      config.entity_restoration_mode = restoration_mode.to_sym
      expect(registry.should_restore?(qcp, config: config)).to eql(restore),
                                                               "should_restore?(" \
                                                               "#{qcp}) " \
                                                               "[#{label}]"
    end
  end
end
