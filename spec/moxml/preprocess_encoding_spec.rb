# frozen_string_literal: true

require "spec_helper"

# lutaml/moxml#604 + lutaml/lutaml-model#1249: the declared-encoding
# rewrite is a document-parse-entry protection (moxml feeds engines
# UTF-8 bytes, so a declaration naming another encoding must be
# rewritten or the bytes decode twice into mojibake). The general
# `preprocess_entities` API also serves text emitters - payloads that
# legitimately BEGIN with an XML declaration (an RFC sourcecode block
# carrying an example document) are verbatim data, and the rewrite
# mutated them. The general path keeps the entity marking and drops
# the rewrite; the rewrite rides the parse-entry variant only.
RSpec.describe "the preprocess encoding scope (#604)" do
  let(:declared_payload) do
    %(<?xml version="1.0" encoding="utf-8"?>\n<EBMLSchema xmlns="urn:ietf:rfc:8794"/>)
  end

  describe "the general path (text emitters)" do
    it "preserves a payload's declared encoding verbatim" do
      processed = Moxml.preprocess_entities(declared_payload)

      expect(processed).to include('encoding="utf-8"')
      expect(processed).not_to include('encoding="UTF-8"?>')
    end

    it "keeps the entity marking behavior" do
      processed = Moxml.preprocess_entities("<a>&nbsp;</a>")

      # non-standard entities are MARKED (the marker lifecycle), not
      # passed through
      expect(processed).to include(Moxml::Entity::MARKER)
    end
  end

  describe "the parse-entry path (engine feeds)" do
    it "still rewrites a foreign declared encoding for the engine" do
      # UTF-8 bytes handed to the engine with a declaration naming
      # iso-8859-1: the rewrite keeps the bytes decoding once
      doc = Moxml.new(:leptris).parse(
        %(<?xml version="1.0" encoding="iso-8859-1"?><a>caf\xc3\xa9</a>),
      )

      expect(doc.root.text).to eq("café")
    end

    it "rewrites the declaration on the parsed document's reparsed form" do
      payload = declared_payload
      doc = Moxml.new(:leptris).parse(payload)

      expect(doc.root.name).to eq("EBMLSchema")
    end
  end
end
