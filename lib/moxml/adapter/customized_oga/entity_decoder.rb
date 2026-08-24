# frozen_string_literal: true

require "oga"

module Moxml
  module Adapter
    module CustomizedOga
      # Override Oga::EntityDecoder.decode for XML inputs.
      #
      # Oga 3.4's stock Oga::XML::Entities.decode runs multiple passes,
      # turning the well-formed "&amp;#38;" into "&" rather than the
      # spec-correct "&#38;". XML 1.0 §4.6 forbids recursive resolution
      # of parsed entities — exactly one decode pass is correct.
      #
      # Moxml::Adapter::Base.decode_entities does the single pass. HTML
      # inputs fall through to Oga's stock HTML::Entities.decode, which
      # has HTML-specific legacy rules that differ from XML's.
      #
      # Prepending on the singleton class means every Oga reader
      # (Text#text, Attribute#value, etc.) automatically picks up the
      # fixed decoder, so the adapter no longer needs to walk the parsed
      # tree rewriting @text/@value ivars behind Oga's back.
      module EntityDecoderOverride
        # rubocop:disable-next Style/OptionalBooleanParameter -- must match Oga's signature
        def decode(input, html = false)
          return super if html

          ::Moxml::Adapter::Base.decode_entities(input)
        end
      end
    end
  end
end

Oga::EntityDecoder.singleton_class.prepend(
  Moxml::Adapter::CustomizedOga::EntityDecoderOverride,
)
