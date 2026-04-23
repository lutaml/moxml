# frozen_string_literal: true

if RUBY_ENGINE == "opal"
  require_relative "native_attachment/opal"
else
  require_relative "native_attachment/native"
end
