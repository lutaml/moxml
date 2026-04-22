# TODO 5: Fixture Integrity and CI Validation

## Problem

The Metanorma bilingual presentation fixture was previously corrupted (error
messages appended after valid XML). It was truncated to fix the corruption,
but the truncated version has not been verified against the upstream source.

Additionally, there is no automated validation of XML fixtures in CI — a
corrupted fixture could be introduced and not caught until round-trip tests
fail with confusing errors.

## Remaining Tasks

### 1. Verify Bilingual Fixture Against Upstream

The file `spec/fixtures/round-trips/metanorma/bilingual.presentation.xml`
was truncated from 111,606 lines to fix corruption. Need to:

- Obtain a clean copy from the Metanorma project
- Compare with the current truncated version (21,211 lines — different from
  the 55,802 lines mentioned in the original TODO, suggesting further changes)
- Confirm no data loss occurred in truncation

### 2. Add CI Fixture Validation

Add a Rake task or RSpec test that validates all XML fixtures are well-formed
before running round-trip tests. This prevents silent corruption.

**Option A**: Rake task using `xmllint`:
```ruby
# In Rakefile
namespace :spec do
  task :validate_fixtures do
    errors = []
    Dir.glob("spec/fixtures/**/*.xml").each do |path|
      output = `xmllint --noout "#{path}" 2>&1`
      errors << "#{path}: #{output}" unless $?.success?
    end
    raise "Invalid fixtures:\n#{errors.join("\n")}" unless errors.empty?
  end
end
task spec: ["spec:validate_fixtures"]
```

**Option B**: RSpec test:
```ruby
# spec/integration/fixture_validation_spec.rb
RSpec.describe "XML fixtures" do
  Dir.glob("spec/fixtures/**/*.xml").each do |path|
    it "#{path} is valid XML" do
      ctx = Moxml.new(:nokogiri)
      expect { ctx.parse(File.read(path)) }.not_to raise_error
    end
  end
end
```

Option A is preferred — `xmllint` is stricter and catches issues that
lenient parsers might silently accept.

## Files to Create/Modify

- `Rakefile` — add `spec:validate_fixtures` task
- Verify/replace `spec/fixtures/round-trips/metanorma/bilingual.presentation.xml`
