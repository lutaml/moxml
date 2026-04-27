# frozen_string_literal: true

module Moxml
  class NativeAttachment
    # Opal adapter nodes are Ruby objects, so instance variables are sufficient
    # for Moxml-owned attachments without relying on Monitor/Thread support.
    class Opal
      def get(native, key)
        native.instance_variable_get(attachment_ivar_name(key))
      end

      def set(native, key, value)
        native.instance_variable_set(attachment_ivar_name(key), value)
      end

      def key?(native, key)
        native.instance_variable_defined?(attachment_ivar_name(key))
      end

      def delete(native, key)
        ivar_name = attachment_ivar_name(key)
        return unless native.instance_variable_defined?(ivar_name)

        native.remove_instance_variable(ivar_name)
      end

      private

      def attachment_ivar_name(key)
        :"@moxml_attachment_#{key}"
      end
    end
  end
end
