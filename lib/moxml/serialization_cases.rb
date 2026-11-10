# frozen_string_literal: true

module Moxml
  # The serialization conformance family (#490 item 8, family 5): the
  # committed element-level serialization answers, one row per shape.
  # Each row's output is the round-trip-correct form — admitted only
  # after parse -> serialize -> parse -> serialize byte-equality on
  # both primary engines. Comparison basis: `doc.root.to_xml(indent: 0)`
  # (element level; the document face carries adapter-divergent
  # trailing newlines). Consumed by `rake conformance:export` and the
  # cross-language runners; rows are the model's answers, so a runner
  # mismatch is a finding, not a data question.
  module SerializationCases
    CONFORMANCE_CASES = [
      ["empty-root", "<r/>", "<r></r>"],
      ["simple-text", "<r>x</r>", "<r>x</r>"],
      ["attr-amp", "<r a=\"x &amp; y\"/>", "<r a=\"x &amp; y\"></r>"],
      ["attr-lt", "<r a=\"1 &lt; 2\"/>", "<r a=\"1 &lt; 2\"></r>"],
      ["attr-quote", "<r a='say \"hi\"'/>",
       "<r a=\"say &quot;hi&quot;\"></r>"],
      ["text-escape", "<r>1 &lt; 2 &amp; 3</r>", "<r>1 &lt; 2 &amp; 3</r>"],
      ["text-gt", "<r>1 &gt; 2</r>", "<r>1 &gt; 2</r>"],
      ["cdata", "<r><![CDATA[a]]><b/></r>",
       "<r><![CDATA[a]]><b></b></r>"],
      ["comment", "<r><!--c--></r>", "<r><!--c--></r>"],
      ["pi", "<r><?pi data?></r>", "<r><?pi data?></r>"],
      ["namespace-default", "<r xmlns=\"urn:x\"><a/></r>",
       "<r xmlns=\"urn:x\"><a></a></r>"],
      ["namespace-prefixed-attr", "<r xmlns:p=\"urn:p\" p:a=\"1\"/>",
       "<r xmlns:p=\"urn:p\" p:a=\"1\"></r>"],
      ["mixed-content", "<r>a<b/>c</r>", "<r>a<b></b>c</r>"],
      ["attr-newline", "<r a=\"x&#10;y\"/>", "<r a=\"x&#10;y\"></r>"],
      ["crlf-text", "<r>a\r\nb</r>", "<r>a\nb</r>"],
      ["combo", "<r a='1'>t&amp;t</r>", "<r a=\"1\">t&amp;t</r>"],
      ["nested-empty", "<r><a><b/></a></r>",
       "<r><a><b></b></a></r>"],
      ["text-apos", "<r>it&apos;s</r>", "<r>it's</r>"],
      ["numeric-ref", "<r>&#65;&#233;</r>", "<r>Aé</r>"],
      ["high-codepoint-attr", "<r a=\"é\"/>", "<r a=\"é\"></r>"],
    ].map(&:freeze).freeze
  end
end
