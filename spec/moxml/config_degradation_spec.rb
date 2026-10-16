# frozen_string_literal: true

require "spec_helper"

# Issue #384: when the preferred default adapter is installed but
# unusable, the silent substitution to the fallback adapter changed
# validation semantics invisibly. The degradation now announces
# itself; an install without the gem at all stays silent (a normal
# deployment shape).
RSpec.describe "Config default-adapter degradation" do
  def with_broken_leptris
    old_default_adapter =
      Moxml::Config.instance_variable_get(:@default_adapter)
    Moxml::Config.remove_instance_variable(:@default_adapter) if old_default_adapter
    # The state a broken install produces (adapter load failure with
    # the gem present): present-but-unusable, not absent.
    Moxml::Config.instance_variable_set(:@leptris_preferred_available, :broken)
    yield
  ensure
    Moxml::Config.remove_instance_variable(:@leptris_preferred_available)
    Moxml::Config.instance_variable_set(:@default_adapter, :nokogiri)
  end

  it "warns loudly and names the fallback" do
    with_broken_leptris do
      expect do
        Moxml::Config.default_adapter
      end.to output(/leptris adapter is installed but unusable/).to_stderr
    end
  end

  it "still answers a usable adapter" do
    with_broken_leptris do
      expect(Moxml::Config.default_adapter).to eq(:nokogiri)
    end
  end

  it "keeps a working leptris install silent" do
    expect do
      Moxml::Config.default_adapter
    end.not_to output(/unusable/).to_stderr
  end
end
