# frozen_string_literal: true

require_relative "../../../ox/node"

module Moxml
  module Adapter
    module CustomizedOx
      # Ox uses Strings, but a string cannot have a parent reference
      class Text < ::Ox::Node; end
    end
  end
end
