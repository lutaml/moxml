# frozen_string_literal: true

module Moxml
  module Reference
    # Pure-Ruby normalization faces: XML 1.0 §2.11 line endings and
    # entity expansion. These are the model's normative answers with
    # no engine involved; adapters are differentially tested against
    # them.
    module Normalizer
      BUILTIN_ENTITIES = {
        "amp" => "&", "lt" => "<", "gt" => ">",
        "quot" => '"', "apos" => "'"
      }.freeze
      ENTITY_REFERENCE = /&([^;&<>]*);/

      module_function

      # CRLF → LF; bare CR → LF. Character references are untouched
      # (&#xD; keeps a literal CR).
      def normalize_eol(text)
        text.to_s.gsub("\r\n", "\n").gsub("\r", "\n")
      end

      # Attribute-value normalization: literal tab/newline/CR become a
      # space (character references keep their value).
      def normalize_attribute_literal(text)
        text.to_s.gsub(/[\t\n\r]/, " ")
      end

      # Expand built-in and numeric references; custom entities come
      # from the provided table. An undefined reference raises a named
      # ParseError (the model has no silently unresolved entities).
      def expand_entities(text, entities = {})
        text.to_s.gsub(ENTITY_REFERENCE) do
          reference = Regexp.last_match(1)
          resolve(reference, BUILTIN_ENTITIES.merge(entities))
        end
      end

      def resolve(reference, entities)
        if reference.start_with?("#x")
          numeric(reference[2..], 16)
        elsif reference.start_with?("#")
          numeric(reference[1..], 10)
        elsif BUILTIN_ENTITIES.key?(reference)
          BUILTIN_ENTITIES[reference]
        else
          value = entities[reference]
          raise ParseError, "undefined entity &#{reference};" unless value

          expand_entities(value, entities)
        end
      end

      def numeric(digits, base)
        pattern = base == 16 ? /\A[0-9A-Fa-f]+\z/ : /\A[0-9]+\z/
        raise ParseError, "malformed character reference" unless digits.match?(pattern)

        [digits.to_i(base)].pack("U")
      end
    end
  end
end
