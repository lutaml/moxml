require_relative "../../../ox/node"

module Moxml
  module Adapter
    module CustomizedOx
      class Namespace
        attr_accessor :prefix, :uri, :parent

        def initialize(prefix, uri, parent = nil)
          @prefix = prefix
          @uri = uri
          @parent = parent
        end

        def prefix
          return if @prefix == "xmlns" || @prefix.nil?

          @prefix.to_s.delete_prefix("xmlns:")
        end

        def expanded_prefix
          ["xmlns", prefix].compact.join(":")
        end

        def default?
          prefix.nil?
        end
      end
    end
  end
end
