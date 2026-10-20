# frozen_string_literal: true

module Moxml
  # RELAX NG schema validation (TODO.sota/05): a facade for engines
  # that ship an RNG validator. Engines without one raise the named
  # Moxml::NotImplementedError — the face is never silently absent.
  #
  #     ctx    = Moxml.new(:leptris)
  #     schema = ctx.relaxng_file("schema.rng")
  #     schema.valid?(doc)            # => true/false
  #     schema.validate_errors(doc)   # => [] or [{line:, column:, message:}]
  #     schema.validate(doc)          # => [] or ["line:col: error: message"]
  #
  # Adapters without an engine raise at compile; RelaxNG.supported?
  # answers without raising (the XSD facade's pattern).
  module RelaxNG
    class << self
      # Whether the context's adapter ships a RELAX NG validator.
      def supported?(context)
        adapter = context.config.adapter
        adapter.const_defined?(:RELAXNG_SUPPORTED) &&
          adapter.const_get(:RELAXNG_SUPPORTED)
      end
    end

    # A compiled schema (adapter-owned handle).
    class Schema
      def initialize(handle, context)
        @handle = handle
        @context = context
      end

      def valid?(document)
        @context.config.adapter.relaxng_valid?(@handle, native(document))
      end

      # Structured report: [{line:, column:, message:}] (empty = valid).
      def validate_errors(document)
        @context.config.adapter
          .relaxng_validate_errors(@handle, native(document))
      end

      # Nokogiri shape: error strings (empty = valid).
      def validate(document)
        validate_errors(document).map do |error|
          line = error[:line]
          if line&.to_i&.positive?
            "#{line}:#{error[:column]}: error: #{error[:message]}"
          else
            error[:message]
          end
        end
      end

      private

      def native(document)
        document.is_a?(Moxml::Document) ? document.native : document
      end
    end
  end
end
