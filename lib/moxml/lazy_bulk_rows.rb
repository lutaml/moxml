# frozen_string_literal: true

module Moxml
  # The leptris adapter's bulk XPath mint, deferred until a caller
  # needs the rows. NodeSet holds this in its lazy slot: #size and
  # #empty? answer from the live result handle (one FFI read), and
  # the first iteration runs Document#xpath_result_rows_bulk once —
  # the same one-crossing mint the eager lane used — then caches the
  # Array. Handling the handle here is load-bearing: the bulk call
  # consumes and frees it, so the GC finalizer is dropped before the
  # call and owns the free only while the rows are still unminted.
  #
  # leptris-ruby#527: the eager mint charged every caller for rows
  # it never asked for; #size on a 1,200-node set paid the whole
  # materialization while the engine answers the count directly.
  class LazyBulkRows
    include LazyNodeSet

    def initialize(document, result_ptr)
      @document = document
      @ptr = result_ptr
      @rows = nil
      ObjectSpace.define_finalizer(
        self, self.class.finalizer(result_ptr.address)
      )
    end

    def length
      @rows ? @rows.length : ::Leptris::XML::FFI.leptris_xpath_result_count(@ptr)
    end

    def empty?
      length.zero?
    end

    def [](index)
      materialize[index]
    end

    def each(&block)
      return enum_for(:each) unless block

      materialize.each(&block)
      self
    end

    def to_a
      materialize
    end

    def self.finalizer(address)
      proc do
        ::Leptris::XML::FFI.leptris_xpath_result_free(
          ::FFI::Pointer.new(address),
        )
      end
    end

    private

    def materialize
      return @rows if @rows

      ObjectSpace.undefine_finalizer(self)
      @rows = @document.xpath_result_rows_bulk(@ptr)
      @ptr = nil
      @rows
    end
  end
end
