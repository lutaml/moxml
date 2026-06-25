# frozen_string_literal: true

require "oga"

module Moxml
  module Adapter
    module CustomizedOga
      # Bypass Oga's lazy decoder for user-authored values.
      #
      # Oga::XML::Attribute#value and Oga::XML::Text#text decode `@value` /
      # `@text` on first read via Oga::EntityDecoder. EntityDecoderOverride
      # makes that decode single-pass for parsed input. But user-authored
      # values are already data — running them through the decoder again
      # would re-interpret any literal `&` / `&#NN;` substrings as entity
      # references. So we route the read through the NativeAttachment
      # sidecar first; if the adapter stored the verbatim value there, we
      # return it as-is, otherwise we fall through to Oga's normal read.
      module RawValueOverride
        def value
          cached = ::Moxml::Adapter::Oga.attachments.get(self, :raw_value)
          return cached unless cached.nil?

          super
        end

        def value=(new_value)
          ::Moxml::Adapter::Oga.attachments.set(self, :raw_value, new_value)
          super
        end

        def text
          cached = ::Moxml::Adapter::Oga.attachments.get(self, :raw_text)
          return cached unless cached.nil?

          super
        end

        def text=(new_value)
          ::Moxml::Adapter::Oga.attachments.set(self, :raw_text, new_value)
          super
        end
      end
    end
  end
end

Oga::XML::Attribute.prepend(
  Moxml::Adapter::CustomizedOga::RawValueOverride,
)
Oga::XML::Text.prepend(
  Moxml::Adapter::CustomizedOga::RawValueOverride,
)
