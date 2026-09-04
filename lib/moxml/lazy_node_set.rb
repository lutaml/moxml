# frozen_string_literal: true

module Moxml
  # Marker for an adapter's native node-set result that NodeSet can
  # hold without materializing the natives. The leptris binding's
  # NodeSet mints one Ruby wrapper per result node in #to_a — the
  # whole 900-node result set is built even when the caller only
  # asks .size or .first — so the adapter hands the native set
  # through instead. Contract: responds to length, empty?, [],
  # each, to_a (yielding natives).
  module LazyNodeSet
    def size
      length
    end
  end
end
