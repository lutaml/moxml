# frozen_string_literal: true

module Moxml
  module RuntimeCompatibility

    module_function

    def opal?
      @opal ||= RUBY_ENGINE == "opal"
    end

    def require_runtime_relative(base_dir, native:, opal:)
      runtime_path = opal? ? opal : native
      require File.expand_path(runtime_path, base_dir)
    end
  end
end
