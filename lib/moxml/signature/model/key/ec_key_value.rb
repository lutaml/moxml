# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      module Key
        # dsig11:ECKeyValue — NamedCurve URI + PublicKey octets, or
        # explicit ECParameters.
        class ECKeyValue
          attr_accessor :named_curve_uri, :public_key, :ec_parameters

          def initialize(named_curve_uri: nil, public_key: nil,
                         ec_parameters: nil)
            @named_curve_uri = named_curve_uri
            @public_key = public_key
            @ec_parameters = ec_parameters
          end
        end
      end
    end
  end
end
