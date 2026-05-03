# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedOx
      # Ox uses Strings for text content, but a String cannot carry a @parent
      # back-reference. We subclass ::Ox::Node so a Text wrapper can hold one.
      #
      # ::Ox::Node subclasses that are neither ::Ox::Element nor ::Ox::Document
      # are unknown to Ox.dump's standard XML emitter, so they fall through to
      # Ox's generic object-marshalling format (`<o c="ClassName"><s a="@ivar">…</s>…</o>`).
      # The serializer in Moxml::Adapter::Ox#serialize special-cases this class
      # to emit @value directly. The #to_s / #inspect overrides below cover the
      # Ruby-idiomatic interpolation paths (`"#{text}"`, `p text`) that would
      # otherwise inherit Object#inspect's `"#<Moxml::…::Text:0xaddr>"` form.
      class Text < ::Ox::Node
        def to_s
          @value.to_s
        end

        alias_method :inspect, :to_s
      end
    end
  end
end
