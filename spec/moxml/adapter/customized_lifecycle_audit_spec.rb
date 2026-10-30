# frozen_string_literal: true

require "spec_helper"

# #495: the Customized* adapter layer is either a removable-lifecycle
# record (an engine gap with a tracked upstream issue) or it dissolves
# into Base. This audit makes the lifecycle record checkable instead of
# folklore: every override file must cite its issue (an #NNN reference
# for our engines, or an upstream tracker URL for third-party engines
# we do not file against), and every Customized module must be wired
# into exactly its adapter (no dead records).
RSpec.describe "Customized adapter lifecycle audit" do
  let(:override_files) do
    Dir[File.expand_path("../../lib/moxml/adapter/customized_*/*.rb", __dir__)].sort
  end

  it "cites a tracked issue or upstream tracker in every override file" do
    broken = override_files.reject do |file|
      head = File.readlines(file).first(25).join
      head.match?(/#\s*#\d{2,5}\b/) || head.include?("github.com/")
    end

    expect(broken).to be_empty, <<~MSG
      Customized* override files without a lifecycle citation:
      #{broken.join("\n")}
      Each file's header must cite the open upstream issue that explains
      why the override exists (#NNN for leptris; the upstream tracker URL
      for third-party engines), or the #491 deprecation that retires it.
    MSG
  end

  it "wires every Customized module into exactly its adapter" do
    shims = Dir[File.expand_path("../../lib/moxml/adapter/customized_*.rb", __dir__)]

    shims.each do |shim|
      module_name = File.read(shim)[/module (Customized\w+)/, 1]
      adapter_file = File.expand_path(
        "../../lib/moxml/adapter/#{module_name.delete_prefix('Customized').downcase}.rb",
        __dir__,
      )

      expect(File).to exist(adapter_file),
                      "#{module_name} has no #{adapter_file} to customize"

      expect(File.read(adapter_file)).to include(module_name),
                                         "#{module_name} is not wired into its adapter"
    end
  end
end
