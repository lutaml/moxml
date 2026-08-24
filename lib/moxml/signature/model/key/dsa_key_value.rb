# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      module Key
        # ds:DSAKeyValue — P, Q, G, Y required; J, Seed, PgenCounter optional.
        # Attribute names mirror the W3C spec §4.5.2.1 element names
        # (P, Q, G, Y, J, Seed, PgenCounter).
        class DSAKeyValue
          attr_accessor :p, :q, :g, :y, :j, :seed, :pgen_counter

          # rubocop:disable-next Naming/MethodParameterName -- P/Q/G/Y/J are W3C spec names
          def initialize(p:, q:, y:, g: nil, j: nil, seed: nil,
                         pgen_counter: nil)
            @p = p
            @q = q
            @y = y
            @g = g
            @j = j
            @seed = seed
            @pgen_counter = pgen_counter
          end
        end
      end
    end
  end
end
