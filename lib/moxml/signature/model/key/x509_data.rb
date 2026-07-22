# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      module Key
        # ds:X509Data (spec §4.5.4) — container for certificate identifiers.
        # May carry X509IssuerSerial, X509SubjectName, X509SKI, X509Certificate,
        # X509CRL, and dsig11:X509Digest children, all describing the same key.
        class X509Data
          attr_accessor :issuer_serial, :subject_name, :subject_key_id,
                        :certificates, :crls, :digests

          def initialize(issuer_serial: nil, subject_name: nil,
                         subject_key_id: nil, certificates: [],
                         crls: [], digests: [])
            @issuer_serial = issuer_serial
            @subject_name = subject_name
            @subject_key_id = subject_key_id
            @certificates = Array(certificates)
            @crls = Array(crls)
            @digests = Array(digests)
          end

          def first_certificate
            certificates.first
          end
        end
      end
    end
  end
end
