# frozen_string_literal: true

module Moxml
  # The c14n conformance family (#490 item 8, family 6): canonical
  # C14N 1.0 vectors (comments dropped — the default digest shape).
  # Every row canonicalizes to IDENTICAL bytes on all seven adapters
  # (the Ruby reference and the leptris native delegation are pinned
  # byte-for-byte by the c14n suite). Consumed by
  # `rake conformance:export` and the cross-language runners.
  module C14nCases
    CONFORMANCE_CASES = [
      ["attr-order", '<r b="2" a="1"/>', '<r a="1" b="2"></r>'],
      ["ns-rewrite",
       '<n:r xmlns:n="urn:n" xmlns:m="urn:m"><n:a m:k="v"/></n:r>',
       '<n:r xmlns:m="urn:m" xmlns:n="urn:n"><n:a m:k="v"></n:a></n:r>'],
      ["ns-hoist", '<r xmlns="urn:x"><a xmlns="urn:y"/></r>',
       '<r xmlns="urn:x"><a xmlns="urn:y"></a></r>'],
      ["text-escape", "<r>1 &lt; 2 &amp; 3</r>", "<r>1 &lt; 2 &amp; 3</r>"],
      ["cdata-to-text", "<r><![CDATA[raw data]]><b/></r>",
       "<r>raw data<b></b></r>"],
      ["comment-dropped", "<r><!--gone--><a/></r>", "<r><a></a></r>"],
      ["pi-kept", "<r><?pi data?><a/></r>", "<r><?pi data?><a></a></r>"],
      ["entity-expanded", "<r>a&lt;b&amp;c</r>", "<r>a&lt;b&amp;c</r>"],
      ["empty-elements", "<r><a/><b></b></r>", "<r><a></a><b></b></r>"],
      ["whitespace-preserved", "<r>  x  <a/>  y  </r>",
       "<r>  x  <a></a>  y  </r>"],
      ["attr-quote-norm", '<r a=\'single "double"\'/>',
       '<r a="single &quot;double&quot;"></r>'],
      ["utf8-high", "<r>café — naïve</r>", "<r>café — naïve</r>"],
      ["nested-ns-default",
       '<r xmlns="urn:a"><c:b xmlns:c="urn:c"><d xmlns="urn:d"/></c:b></r>',
       '<r xmlns="urn:a"><c:b xmlns:c="urn:c"><d xmlns="urn:d"></d></c:b></r>'],
      ["mixed-attrs-ns",
       '<r xmlns:p="urn:p" p:a="1" b="2" xmlns:q="urn:q" q:c="3"/>',
       '<r xmlns:p="urn:p" xmlns:q="urn:q" b="2" p:a="1" q:c="3"></r>'],
    ].map(&:freeze).freeze
  end
end
