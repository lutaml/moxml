# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedOx
      # Ox uses Strings for text content, but a String cannot carry a @parent
      # back-reference. We subclass ::Ox::Node so a Text wrapper can hold one.
      #
      # ::Ox::Node subclasses that are neither ::Ox::Element nor ::Ox::Document
      # are unknown to Ox.dump's standard XML emitter, so they fall through to
      # Ox's generic object-marshalling format. The serializer in
      # Moxml::Adapter::Ox#serialize special-cases this class to emit the value
      # with proper XML escaping. The #to_s override ensures string
      # interpolation (`"#{text}"`) produces the text content rather than the
      # default Object representation.
      class Text < ::Ox::Node
        def to_s
          value.to_s
        end
      end
    end
  end
end
