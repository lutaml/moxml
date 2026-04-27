# frozen_string_literal: true

module Moxml
  class NativeAttachment
    autoload :Opal, "moxml/native_attachment/opal"
    autoload :Native, "moxml/native_attachment/native"

    def self.default_backend
      constant = RUBY_ENGINE == "opal" ? :Opal : :Native
      const_get(constant).new
    end

    attr_reader :backend

    def initialize(backend: self.class.default_backend)
      @backend = backend
    end

    def get(native, key)
      @backend.get(native, key)
    end

    def set(native, key, value)
      @backend.set(native, key, value)
    end

    def key?(native, key)
      @backend.key?(native, key)
    end

    def delete(native, key)
      @backend.delete(native, key)
    end
  end
end
