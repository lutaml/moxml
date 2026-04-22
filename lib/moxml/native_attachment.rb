# frozen_string_literal: true

module Moxml
  # Stores Moxml-specific state associated with native adapter objects
  # without polluting their internals.
  #
  # Uses object_id as key with GC finalizer cleanup to prevent memory leaks.
  # Thread-safe via Monitor (reentrant-safe).
  #
  # Replaces the anti-pattern of using instance_variable_set/get on
  # foreign library objects (Nokogiri, REXML, Oga, Ox, LibXML nodes).
  #
  # @example
  #   attachments = NativeAttachment.new
  #   attachments.set(native_element, :entity_refs, [])
  #   refs = attachments.get(native_element, :entity_refs)
  #   attachments.key?(native_element, :doctype) #=> false
  class NativeAttachment
    def initialize
      @data = {}
      @finalizer_registered = {}
      @monitor = Monitor.new
    end

    def get(native, key)
      @monitor.synchronize { @data[native.object_id]&.[](key) }
    end

    def set(native, key, value)
      id = native.object_id
      @monitor.synchronize do
        @data[id] ||= {}
        @data[id][key] = value
        register_finalizer(native, id) unless @finalizer_registered[id]
      end
    end

    def key?(native, key)
      @monitor.synchronize { @data[native.object_id]&.key?(key) || false }
    end

    def delete(native, key)
      @monitor.synchronize { @data[native.object_id]&.delete(key) }
    end

    private

    def register_finalizer(native, id)
      @finalizer_registered[id] = true
      ObjectSpace.define_finalizer(native, finalizer_for(id))
    end

    def finalizer_for(id)
      data = @data
      registered = @finalizer_registered
      # Finalizers must NOT use Mutex/Monitor (can't be called from trap context).
      # Direct Hash operations are safe here since finalizers run sequentially
      # and the GC'd object's id won't be accessed by any other thread.
      proc do
        data.delete(id)
        registered.delete(id)
      end
    end
  end
end
