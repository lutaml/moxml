# frozen_string_literal: true

module Moxml
  class NativeAttachment
    autoload :Native, "moxml/native_attachment/native"

    def self.default_backend
      const_get(:Native).new
    end

    attr_reader :backend

    def initialize(backend: self.class.default_backend)
      @backend = backend
    end

    def get(native, key)
      @backend.get(native, key)
    end

    # One probe for "none of these keys are set" — the document
    # serialize gate asks about four keys per call.
    def none_set?(native, keys)
      @backend.none_set?(native, keys)
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
