# frozen_string_literal: true

require_relative "runtime_compatibility"

Moxml::RuntimeCompatibility.require_runtime_relative(
  __dir__,
  native: "native_attachment/native",
  opal: "native_attachment/opal",
)
