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

    # (context, adapter): the consumer contract triple for the primed
    # mint (TODO.perf/40, leptris-ruby#622 ask 2) — the bulk face
    # writes @mx_context/@mx_adapter in C and extends all-native
    # results with BulkIdentityRows, so NodeSet's per-row wrap prime
    # disappears from the iterate-every-result lane. nil (older
    # bindings) keeps the unprimed mint.
    def initialize(document, result_ptr, context = nil, adapter = nil)
      @document = document
      @ptr = result_ptr
      @context = context
      @adapter = adapter
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
      @rows = @document.xpath_result_rows_bulk(@ptr, @context, @adapter)
      @ptr = nil
      @rows
    end
  end
end
