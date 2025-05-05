module Moxml
  module Adapter
    module CustomizedRexml
      # Wrapper to provide .native method expected by tests
      class Wrapper
        attr_reader :native
        
        def initialize(native_obj)
          @native = native_obj
        end
        
        def method_missing(method, *args, &block)
          if method == :text && @native.is_a?(::REXML::Text)
            @native.value #.strip
          elsif method == :to_xml
            if @native.is_a?(::REXML::Attribute)
              value = escape_attribute_value(@native.value.to_s)
              prefix = @native.prefix ? "#{@native.prefix}:" : ""
              %{#{prefix}#{@native.name}="#{value}"}
            elsif @native.is_a?(String)
              escape_attribute_value(@native.to_s)
            else
              @native.to_s
            end
          elsif method == :value
            if @native.is_a?(::REXML::Attribute)
              @native.value
            elsif @native.is_a?(String)
              @native
            end
          elsif method == :value= && @native.is_a?(::REXML::Attribute)
            @native.remove
            element = @native.element
            name = @native.expanded_name
            prefix = @native.prefix
            value = args.first.to_s
            
            # Remove old attribute
            @native.remove
            
            if prefix
              # Find namespace URI in current scope
              current = element
              while current
                if current.respond_to?(:attributes)
                  ns_attr = current.attributes["xmlns:#{prefix}"]
                  if ns_attr
                    # Create namespaced attribute
                    attr = ::REXML::Attribute.new(name, value)
                    attr.add_namespace(prefix, ns_attr.value)
                    element.add_attribute(attr)
                    @native = attr
                    break
                  end
                end
                current = current.parent
              end
              # If no namespace found, create without namespace
              if !current
                element.add_attribute(name, value)
                @native = element.attributes[name]
              end
            else
              # Regular attribute
              element.add_attribute(name, value)
              @native = element.attributes[name]
            end
          else
            @native.send(method, *args, &block)
          end
        end
        
        def respond_to_missing?(method, include_private = false)
          if method == :text && @native.is_a?(::REXML::Text)
            true
          elsif method == :to_xml
            true
          elsif method == :value && (@native.is_a?(::REXML::Attribute) || @native.is_a?(String))
            true
          elsif method == :value= && @native.is_a?(::REXML::Attribute)
            true
          else
            @native.respond_to?(method, include_private)
          end
        end

        def ==(other)
          return false unless other.is_a?(Wrapper) || other.is_a?(::REXML::Element)
          if @native.is_a?(::REXML::Attribute) && other.respond_to?(:native) && other.native.is_a?(::REXML::Attribute)
            @native.value == other.native.value && @native.name == other.native.name
          else
            other_native = other.is_a?(Wrapper) ? other.native : other
            @native == other_native
          end
        end

        private

        def escape_attribute_value(value)
          value.to_s.gsub(/[<>&"']/) do |match|
            case match
            when '<' then '&lt;'
            when '>' then '&gt;'
            when '&' then '&amp;'
            when '"' then '&quot;'
            when "'" then '&apos;'
            end
          end
        end
      end
    end
  end
end
