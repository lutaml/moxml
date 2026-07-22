# Moxml::Signature — Architecture

## Where it lives

`Moxml::Signature` is a sub-module of moxml that implements W3C XML
Signature (xmldsig-core-1.1). It is **XML implementation agnostic** —
every XML operation flows through `Moxml::Document` / `Moxml::Element`,
so the same signature code works whether you parse with Nokogiri, Oga,
REXML, Ox, or LibXML.

C14N itself is a top-level `Moxml::C14n` feature, sibling to
`Moxml::XPath`, `Moxml::Builder`, and `Moxml::SAX`. Signature uses it;
so can any other consumer (e.g., the sibling `canon` gem).

## Module layout

```
lib/moxml.rb                              # top-level, autoloads Signature and C14n
lib/moxml/signature.rb                    # Signature namespace + .sign/.verify entry points

lib/moxml/signature/errors.rb             # error hierarchy
lib/moxml/signature/algorithms.rb         # OCP registry hub
lib/moxml/signature/algorithms/           # concrete algorithms (digests, sig methods, transforms)
lib/moxml/signature/model/                # PORO models
lib/moxml/signature/serializer.rb         # model → XML (uses moxml primitives)
lib/moxml/signature/parser.rb             # XML → model
lib/moxml/signature/reference_resolver.rb # Reference URI → node-set / octets
lib/moxml/signature/transform_pipeline.rb # shared transform chain (DRY)
lib/moxml/signature/signer.rb             # spec §3.1 signing flow
lib/moxml/signature/verifier.rb           # spec §3.2 verification flow
lib/moxml/signature/key_extractor.rb      # X509 / RSA / DSA / EC / KeyName → OpenSSL key
lib/moxml/signature/verification_result.rb
lib/moxml/signature/single_verification_result.rb
lib/moxml/signature/reference_result.rb

lib/moxml/c14n.rb                         # top-level C14n namespace
lib/moxml/c14n/                           # canon-ported engine + moxml-native Exclusive
```

## Layering

```
┌──────────────────────────────────────────────────────────────────┐
│ Application code                                                 │
│   Moxml::Signature.sign / .verify                                │
└──────────────────────────────────────────────────────────────────┘
                                ↕
┌──────────────────────────────────────────────────────────────────┐
│ Orchestration:  Signer, Verifier, TransformPipeline, KeyExtractor│
└──────────────────────────────────────────────────────────────────┘
                                ↕
┌──────────────────────┐   ┌──────────────────────────────────────┐
│ Algorithms (OCP hub) │   │ Models: Signature, SignedInfo, etc.  │
└──────────────────────┘   └──────────────────────────────────────┘
                                ↕
┌──────────────────────────────────────────────────────────────────┐
│ Moxml::C14n (canon-ported Inclusive + moxml-native Exclusive)    │
└──────────────────────────────────────────────────────────────────┘
                                ↕
┌──────────────────────────────────────────────────────────────────┐
│ Moxml::Document / Element / Text / Namespace / Attribute          │
│   (adapter-agnostic — Nokogiri, Oga, REXML, Ox, LibXML)           │
└──────────────────────────────────────────────────────────────────┘
                                ↕
                          OpenSSL (crypto)
```

## Core design decisions

### 1. Algorithm registry as the OCP hub

Every W3C algorithm (digest, signature method, canonicalization,
transform) is identified by URI. The `Moxml::Signature::Algorithms`
module is the registry; adding a new algorithm means:

1. Subclass the relevant base (`DigestBase`, `SignatureMethodBase`,
   `CanonicalizationBase`, `TransformBase`).
2. Declare `identifier "http://..."` on the subclass.
3. Add an autoload entry in `algorithms.rb` and a reference in
   `load_builtins!`.

No edits to existing code. The registry has four categories:
`:digest`, `:signature_method`, `:canonicalization`, `:transform`.

### 2. Models are POROs; serialization is a service

Models (`Model::Signature`, `Model::SignedInfo`, `Model::Reference`,
etc.) are plain Ruby objects with `attr_accessor`. They do **not** own
their wire shape. A dedicated `Serializer` translates model → XML using
moxml primitives; `Parser` translates XML → model. This keeps the data
shape and the wire shape independent, and matches the user's global
rule ("no hand-rolled serialization on model classes").

### 3. Signer / Verifier orchestrate, don't compute

`Signer` walks the references, delegates to the transform pipeline,
computes digests via `DigestMethod` instances, and signs the
canonicalized SignedInfo. It contains no algorithm-specific logic.

`Verifier` follows Best Practice 1: authenticate SignatureValue first,
then run reference transforms. Errors are captured into the result
object (`SingleVerificationResult#error`), not raised, so a malicious
signature cannot panic the application.

### 4. TransformPipeline is shared by Signer and Verifier

The transform-chain logic (lookup algorithm, coerce input type, apply,
repeat) is the same for signing and verifying. It lives in
`TransformPipeline` — DRY.

### 5. C14N is shared infrastructure

Inclusive C14N is ported from `~/src/lutaml/canon` (mature, ~1,200
lines, full node-set subset support, xml:base fixup, xml:* inheritable
attribute resolution). Exclusive C14N is moxml-native (canon doesn't
implement it). Both expose the same `#canonicalize(node, with_comments:,
inclusive_namespaces:)` interface.

## Adapter-agnostic invariant

Every XML operation — parse, walk, serialize, canonicalize — goes
through `Moxml::Node`. The signature module never imports Nokogiri,
Oga, REXML, Ox, or LibXML directly. Switching adapters does not change
signature behavior.

The one exception is the `context:` parameter threaded through every
constructor. When a transform receives octet-stream input, it parses
with the same adapter the caller used (`context.parse(...)`), preserving
byte-exact canonicalization across adapters.

## Cross-verification

`spec/fixtures/xmldsig/sign2-result.xml` and `sign3-result.xml` are
real libxmlsec1-produced signatures (from the Ruby
`nokogiri-xmlsec-instructure` reference). Both verify byte-exact against
`Moxml::Signature.verify`, proving the C14N and signing logic matches a
battle-tested C implementation.

## What this module deliberately doesn't do

- **XPath Filter transform** — Best Practice 5 says avoid. The Enveloped
  Signature transform walks ancestors directly, no XPath needed.
- **XSLT transform** — Best Practice 3 says avoid. Disabled.
- **External URI dereferencing** — Best Practice 8 says constrain.
  Applications must provide their own resolver.
- **X.509 chain validation** — application responsibility (trust policy).
- **XML Encryption** — separate spec (xmlenc-core-1.1).
- **XAdES** — separate spec (ETSI TS 101 903).
