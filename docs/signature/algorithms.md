# Algorithm registry

The `Moxml::Signature::Algorithms` module is the open-closed hub for
all W3C XML Signature algorithms. Algorithms are identified by URI;
the registry maps URI → class for each of four categories:

| Category             | W3C spec section | Base class                                    |
| -------------------- | ---------------- | --------------------------------------------- |
| `:digest`            | §6.2             | `Algorithms::DigestBase`                      |
| `:signature_method`  | §6.3, §6.4       | `Algorithms::SignatureMethodBase`             |
| `:canonicalization`  | §6.5             | `Algorithms::CanonicalizationBase`            |
| `:transform`         | §6.6             | `Algorithms::TransformBase`                   |

## Built-in algorithms

### Digests (§6.2)

| URI                                                        | Class            |
| ---------------------------------------------------------- | ---------------- |
| `http://www.w3.org/2000/09/xmldsig#sha1`                   | `SHA1`           |
| `http://www.w3.org/2001/04/xmldsig-more#sha224`            | `SHA224`         |
| `http://www.w3.org/2001/04/xmlenc#sha256` (REQUIRED)       | `SHA256`         |
| `http://www.w3.org/2001/04/xmldsig-more#sha384`            | `SHA384`         |
| `http://www.w3.org/2001/04/xmlenc#sha512`                  | `SHA512`         |

### Signature methods (§6.3, §6.4)

| URI                                                        | Class            | Notes |
| ---------------------------------------------------------- | ---------------- | ----- |
| `…xmldsig#rsa-sha1`                                        | `RsaPkcs1Sha`    | Verification only (BP: SHA-1 discouraged) |
| `…xmldsig-more#rsa-sha224`                                 | `RsaPkcs1Sha`    | |
| `…xmldsig-more#rsa-sha256` (REQUIRED)                      | `RsaPkcs1Sha`    | |
| `…xmldsig-more#rsa-sha384`                                 | `RsaPkcs1Sha`    | |
| `…xmldsig-more#rsa-sha512`                                 | `RsaPkcs1Sha`    | |
| `…xmldsig#hmac-sha1`                                       | `HmacSha`        | Truncation enforced per §4.4.2 |
| `…xmldsig-more#hmac-sha224`                                | `HmacSha`        | |
| `…xmldsig-more#hmac-sha256` (REQUIRED)                     | `HmacSha`        | |
| `…xmldsig-more#hmac-sha384`                                | `HmacSha`        | |
| `…xmldsig-more#hmac-sha512`                                | `HmacSha`        | |
| `…xmldsig-more#ecdsa-sha1`                                 | `EcdsaSha`       | |
| `…xmldsig-more#ecdsa-sha224`                               | `EcdsaSha`       | |
| `…xmldsig-more#ecdsa-sha256` (REQUIRED)                    | `EcdsaSha`       | P-256/P-384/P-521 |
| `…xmldsig-more#ecdsa-sha384`                               | `EcdsaSha`       | |
| `…xmldsig-more#ecdsa-sha512`                               | `EcdsaSha`       | |
| `…xmldsig#dsa-sha1`                                        | `DsaSha`         | |
| `…xmldsig11#dsa-sha256`                                    | `DsaSha`         | |

### Canonicalization (§6.5)

| URI                                                        | Engine                       |
| ---------------------------------------------------------- | ---------------------------- |
| `http://www.w3.org/TR/2001/REC-xml-c14n-20010315`          | `Moxml::C14n::Inclusive10` (canon-ported) |
| `…REC-xml-c14n-20010315#WithComments`                      | same, `with_comments: true`  |
| `http://www.w3.org/2006/12/xml-c14n11`                     | `Moxml::C14n::Inclusive11`   |
| `…xml-c14n11#WithComments`                                 | same, `with_comments: true`  |
| `http://www.w3.org/2001/10/xml-exc-c14n#`                  | `Moxml::C14n::Exclusive` (moxml-native) |
| `…xml-exc-c14n#WithComments`                               | same, `with_comments: true`  |

### Transforms (§6.6)

| URI                                                        | Class                          |
| ---------------------------------------------------------- | ------------------------------ |
| `http://www.w3.org/2000/09/xmldsig#base64`                 | `Base64Transform`              |
| `http://www.w3.org/2000/09/xmldsig#enveloped-signature`    | `EnvelopedSignatureTransform`  |

Canonicalization algorithms can also be used as transforms per §6.6.1.
The `TransformPipeline` looks them up in the canonicalization registry
as a fallback.

## Adding a custom algorithm

```ruby
require "moxml/signature"

module MyAlgo
  class SHA3_256 < Moxml::Signature::Algorithms::DigestBase
    identifier "http://www.w3.org/2007/xmldsig-more#sha3-256"

    def compute_digest(data)
      OpenSSL::Digest.digest("SHA3-256", data)
    end
  end
end

# Now the URI resolves:
Moxml::Signature::Algorithms.lookup(
  :digest,
  "http://www.w3.org/2007/xmldsig-more#sha3-256",
)
# => MyAlgo::SHA3_256
```

The `identifier` declaration registers the class on load. No edits to
existing code are required — pure OCP.

## API

```ruby
Algorithms.lookup(:digest, uri)       # → class, raises UnknownAlgorithm
Algorithms.registered?(:digest, uri)  # → bool
Algorithms[:digest]                   # → { uri => class, ... }
```

## Lazy loading

The registry autoloads built-in algorithm classes on first lookup
(`load_builtins!` references each constant, triggering autoload).
Custom algorithms register themselves on `require` of their file.
