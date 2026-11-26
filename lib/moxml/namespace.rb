# frozen_string_literal: true

module Moxml
  module Namespace
    include Node

    def prefix
      adapter.namespace_prefix(@native)
    end

    def uri
      adapter.namespace_uri(@native)
    end

    # Nokogiri parity (#582 gap 5): the migration idiom reads
    # node.namespace&.href — same value as #uri.
    def href
      uri
    end

    def ==(other)
      other.is_a?(Namespace) && prefix == other.prefix && uri == other.uri
    end

    def to_s
      if prefix && prefix != "xmlns"
        %(xmlns:#{prefix}="#{uri}")
      else
        %(xmlns="#{uri}")
      end
    end

    def default?
      prefix.nil? || prefix.to_s == "xmlns"
    end

    def namespace?
      true
    end
  end
end
