# frozen_string_literal: true

require "spec_helper"

# Issue #384: when the preferred default adapter is installed but
# unusable, the silent substitution to the fallback adapter changed
# validation semantics invisibly. The degradation now announces
# itself; an install without the gem at all stays silent (a normal
# deployment shape).
RSpec.describe "Config default-adapter degradation" do
  # Cold selection without ivar access: the public reset clears the
  # memoized probe verdict, resolved default name, and default
  # Config instance (moxml#523 seam). The ambient default name is
  # captured before the reset and re-pinned through the public
  # writer afterwards — the surrounding suite may depend on a
  # default pinned at require time (canon pins nokogiri).
  def with_cold_selection
    ambient = Moxml::Config.default_adapter
    Moxml::Config.reset_adapter_selection!
    yield
  ensure
    Moxml::Config.default_adapter = ambient
  end

  # The state a broken install produces: the gem is present and
  # loads, but the engine's native build fails — simulated at the
  # probe seam the selection actually consults (#523). A broken lane
  # ENDS on the fallback adapter, so after the example the broken
  # examples leave nokogiri pinned (the state consumers actually
  # run under) — pinned AFTER with_cold_selection's ambient restore.
  def with_broken_leptris
    with_cold_selection do
      allow(Moxml::Config).to receive(:leptris_native_probe).and_raise(
        Moxml::AdapterError.new(
          "plan result build failed (status=-5)",
          adapter: :leptris,
          operation: "probe",
        ),
      )
      yield
    end
    Moxml::Config.default_adapter = :nokogiri
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
    with_cold_selection do
      expect do
        Moxml::Config.default_adapter
      end.not_to output(/unusable/).to_stderr
    end
  end

  # moxml#523: bundle presence is not capability. Under broken-ABI
  # rubies (Ruby 4.0 plan builds answer status=-5, leptris#1966) a
  # present leptris poisoned the whole lane. Selection now runs a
  # one-shot parse+serialize probe and treats failure as
  # present-but-unusable: loud warning, nokogiri fallback.
  describe "native capability probe (#523)" do
    before do
      present = Gem::Specification.find_by_name("leptris")
      skip "leptris gem not available" unless present
    rescue Gem::LoadError
      skip "leptris gem not available"
    end

    def with_failing_native_probe
      with_cold_selection do
        allow(Moxml::Adapter::Leptris).to receive(:parse).and_raise(
          Moxml::AdapterError.new(
            "plan result build failed (status=-5)",
            adapter: :leptris,
            operation: "parse",
          ),
        )
        yield
      end
    end

    it "falls back loudly when the native build fails the probe" do
      with_failing_native_probe do
        expect do
          expect(Moxml::Config.default_adapter).to eq(:nokogiri)
        end.to output(/leptris adapter is installed but unusable/).to_stderr
      end
    end

    it "memoizes the failed probe (one run per process)" do
      with_failing_native_probe do
        expect(Moxml::Config.leptris_preferred_available?).to eq(:broken)
        expect(Moxml::Adapter::Leptris).not_to(receive(:parse))
        expect(Moxml::Config.leptris_preferred_available?).to eq(:broken)
      end
    end

    it "keeps leptris when the probe passes on a healthy stack" do
      with_cold_selection do
        expect(Moxml::Config.default_adapter).to eq(:leptris)
      end
    end
  end
end
