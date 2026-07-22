# XML Signature Syntax and Processing Version 1.1 (W3C Recommendation, 11 April 2013)

Curated implementation-focused extract. Source: https://www.w3.org/TR/xmldsig-core/

Editors: Donald Eastlake, Joseph Reagle, David Solo, Frederick Hirsch, Magnus Nyström, Thomas Roessler, Kelvin Yiu.

## Abstract

XML Signatures provide integrity, message authentication, and/or signer
authentication services for data of any type, whether located within the XML
that includes the signature or elsewhere.

## Namespaces

| URI | prefix |
| --- | --- |
| `http://www.w3.org/2000/09/xmldsig#` | `ds:` / `dsig:` |
| `http://www.w3.org/2009/xmldsig11#` | `dsig11:` |

Algorithm identifiers in the `http://www.w3.org/2001/04/xmldsig-more#` namespace
are defined by RFC 6931.

## Signature Structure

```
<Signature ID?>
  <SignedInfo>
    <CanonicalizationMethod />
    <SignatureMethod />
   (<Reference URI? >
     (<Transforms>)?
      <DigestMethod>
      <DigestValue>
    </Reference>)+
  </SignedInfo>
  <SignatureValue>
 (<KeyInfo>)?
 (<Object ID?>)*
</Signature>
```

## Processing Rules

### 3.1 Signature Generation

#### 3.1.1 Reference Generation

For each data object being signed:

1. Apply the `Transforms`, as determined by the application, to the data object.
2. Calculate the digest value over the resulting data object.
3. Create a `Reference` element, including the (optional) identification of the
   data object, any (optional) transform elements, the digest algorithm and the
   `DigestValue`.

#### 3.1.2 Signature Generation

1. Create `SignedInfo` element with `SignatureMethod`, `CanonicalizationMethod`
   and `Reference`(s).
2. Canonicalize and then calculate the `SignatureValue` over `SignedInfo` based
   on algorithms specified in `SignedInfo`.
3. Construct the `Signature` element that includes `SignedInfo`, `Object`(s),
   `KeyInfo` (if required), and `SignatureValue`.

### 3.2 Core Validation

The required steps of core validation include:

1. **Reference validation** — verification of the digest contained in each
   `Reference` in `SignedInfo`.
2. **Signature validation** — cryptographic signature validation of the signature
   calculated over `SignedInfo`.

Comparison of each value is over the numeric (integer) or decoded octet sequence
of the value.

#### 3.2.1 Reference Validation

1. Canonicalize the `SignedInfo` element based on the `CanonicalizationMethod`.
2. For each `Reference` in `SignedInfo`:
   1. Obtain the data object (dereference `URI`, execute `Transforms`, or fetch
      from local cache).
   2. Digest using the `DigestMethod`.
   3. Compare against `DigestValue`; mismatch ⇒ validation fails.

#### 3.2.2 Signature Validation

1. Obtain the keying information from `KeyInfo` or external source.
2. Obtain the canonical form of `SignedInfo` using `CanonicalizationMethod` and
   confirm the `SignatureValue` over `SignedInfo`.

## Schema

### `ds:CryptoBinary`

Integer-to-octet conversion equivalent to IEEE 1363 I2OSP with minimal length,
then base64-encoded.

### 4.2 `Signature`

```xml
<element name="Signature" type="ds:SignatureType"/>
<complexType name="SignatureType">
  <sequence>
    <element ref="ds:SignedInfo"/>
    <element ref="ds:SignatureValue"/>
    <element ref="ds:KeyInfo" minOccurs="0"/>
    <element ref="ds:Object" minOccurs="0" maxOccurs="unbounded"/>
  </sequence>
  <attribute name="Id" type="ID" use="optional"/>
</complexType>
```

### 4.3 `SignatureValue`

```xml
<complexType name="SignatureValueType">
  <simpleContent>
    <extension base="base64Binary">
      <attribute name="Id" type="ID" use="optional"/>
    </extension>
  </simpleContent>
</complexType>
```

### 4.4 `SignedInfo`

```xml
<complexType name="SignedInfoType">
  <sequence>
    <element ref="ds:CanonicalizationMethod"/>
    <element ref="ds:SignatureMethod"/>
    <element ref="ds:Reference" maxOccurs="unbounded"/>
  </sequence>
  <attribute name="Id" type="ID" use="optional"/>
</complexType>
```

### 4.4.1 `CanonicalizationMethod`

```xml
<complexType name="CanonicalizationMethodType" mixed="true">
  <sequence>
    <any namespace="##any" minOccurs="0" maxOccurs="unbounded"/>
  </sequence>
  <attribute name="Algorithm" type="anyURI" use="required"/>
</complexType>
```

### 4.4.2 `SignatureMethod`

```xml
<complexType name="SignatureMethodType" mixed="true">
  <sequence>
    <element name="HMACOutputLength" minOccurs="0" type="ds:HMACOutputLengthType"/>
    <any namespace="##other" minOccurs="0" maxOccurs="unbounded"/>
  </sequence>
  <attribute name="Algorithm" type="anyURI" use="required"/>
</complexType>
```

Signatures MUST be deemed invalid if the HMAC truncation length is below the
larger of (a) half the underlying hash output length, and (b) 80 bits.

### 4.4.3 `Reference`

```xml
<complexType name="ReferenceType">
  <sequence>
    <element ref="ds:Transforms" minOccurs="0"/>
    <element ref="ds:DigestMethod"/>
    <element ref="ds:DigestValue"/>
  </sequence>
  <attribute name="Id" type="ID" use="optional"/>
  <attribute name="URI" type="anyURI" use="optional"/>
  <attribute name="Type" type="anyURI" use="optional"/>
</complexType>
```

#### 4.4.3.2 Reference Processing Model

Result of URI dereferencing or transforms is either octet stream or XPath node-set.

Defaults:
- octet stream + node-set transform expected ⇒ parse octets as XML.
- node-set + octet transform expected ⇒ canonicalize via C14N.

A **same-document reference** is a URI-Reference that consists of `#` followed by
a fragment, or an empty URI.

- `URI=""` ⇒ node-set (minus comments) of the entire document.
- `URI="#id"` ⇒ node-set of the element with that ID + descendants + in-scope
  namespaces/attributes, no comments.
- `#xpointer(/)` retains comments at root.
- `#xpointer(id('ID'))` retains comments for the element.

### 4.4.3.4 `Transforms`

```xml
<complexType name="TransformsType">
  <sequence>
    <element ref="ds:Transform" maxOccurs="unbounded"/>
  </sequence>
</complexType>

<complexType name="TransformType" mixed="true">
  <choice minOccurs="0" maxOccurs="unbounded">
    <any namespace="##other" processContents="lax"/>
    <element name="XPath" type="string"/>
  </choice>
  <attribute name="Algorithm" type="anyURI" use="required"/>
</complexType>
```

### 4.5 `KeyInfo`

```xml
<complexType name="KeyInfoType" mixed="true">
  <choice maxOccurs="unbounded">
    <element ref="ds:KeyName"/>
    <element ref="ds:KeyValue"/>
    <element ref="ds:RetrievalMethod"/>
    <element ref="ds:X509Data"/>
    <element ref="ds:PGPData"/>
    <element ref="ds:SPKIData"/>
    <element ref="ds:MgmtData"/>
    <any processContents="lax" namespace="##other"/>
  </choice>
  <attribute name="Id" type="ID" use="optional"/>
</complexType>
```

`KeyValue` contains one of `DSAKeyValue`, `RSAKeyValue`, or (1.1) `ECKeyValue`.

X509Data child elements: `X509IssuerSerial` (deprecated), `X509SKI`,
`X509SubjectName`, `X509Certificate`, `X509CRL`, `dsig11:X509Digest`.

### 4.6 `Object`

Optional element for including data objects. Has `Id`, `MimeType`, `Encoding`
attributes.

## Additional Syntax

### 5.1 `Manifest`

A list of `Reference`s where digest checking is application-defined (not core).

### 5.2 `SignatureProperties`

For signature-time, hardware serial, etc. `SignatureProperty` has required
`Target` attribute referencing the `Signature` element.

### 5.3 PIs and 5.4 Comments

Unless `CanonicalizationMethod` strips comments or PIs, they are signed.

## Algorithms

### Mandatory & Recommended URIs

**Digest**:
- Required: SHA1 `http://www.w3.org/2000/09/xmldsig#sha1` (discouraged); SHA256
  `http://www.w3.org/2001/04/xmlenc#sha256`
- Optional: SHA224 `…xmldsig-more#sha224`; SHA384 `…xmldsig-more#sha384`; SHA512
  `…xmlenc#sha512`

**MAC**:
- Required: HMAC-SHA1 `…xmldsig#hmac-sha1` (discouraged); HMAC-SHA256
  `…xmldsig-more#hmac-sha256`
- Recommended: HMAC-SHA384, HMAC-SHA512

**Signature**:
- Required: RSA-SHA256 `…xmldsig-more#rsa-sha256`; ECDSA-SHA256
  `…xmldsig-more#ecdsa-sha256`; DSA-SHA1 (verification only) `…xmldsig#dsa-sha1`
- Recommended: RSA-SHA1 (verification; discouraged for generation)
- Optional: RSA-{SHA224,SHA384,SHA512}; ECDSA-{SHA1,SHA224,SHA384,SHA512};
  DSA-SHA256 `…xmldsig11#dsa-sha256`

**Canonicalization**:
- Required:
  - Canonical XML 1.0 (omit comments): `http://www.w3.org/TR/2001/REC-xml-c14n-20010315`
  - Canonical XML 1.1 (omit comments): `http://www.w3.org/2006/12/xml-c14n11`
  - Exclusive XML Canonicalization 1.0 (omit comments): `http://www.w3.org/2001/10/xml-exc-c14n#`
- Recommended variants append `#WithComments`

**Transform**:
- Required: base64 `…xmldsig#base64`; Enveloped Signature
  `…xmldsig#enveloped-signature`
- Recommended: XPath `…REC-xpath-19991116`; XPath Filter 2.0
  `…2002/06/xmldsig-filter2`
- Optional: XSLT `…REC-xslt-19991116`

### Digest Algorithms

- SHA-1: 160-bit / 20 octets, base64-encoded.
- SHA-256: 256-bit / 32 octets.
- SHA-384: 384-bit / 48 octets.
- SHA-512: 512-bit / 64 octets.

### HMAC

Identifier family: `…xmldsig#hmac-sha1`, `…xmldsig-more#hmac-{sha224,sha256,sha384,sha512}`.
Truncation length (`HMACOutputLength`) MUST be a multiple of 8 bits. If below
half the hash output length, signature MUST be deemed invalid.

### DSA

Identifier: `…xmldsig#dsa-sha1` (1024/160), `…xmldsig11#dsa-sha256` (2048/256 or
3072/256).

Output (r, s): base64-encoded concatenation of two octet streams using I2OSP with
length parameter 20 (for SHA-1) or `N` (for SHA-256 with N=|q|).

### RSA (PKCS#1 v1.5)

Identifiers: `…xmldsig#rsa-sha1`, `…xmldsig-more#rsa-{sha224,sha256,sha384,sha512}`.
RSASSA-PKCS1-v1_5 per RFC 3447 §8.2.1.

### ECDSA

Identifiers: `…xmldsig-more#ecdsa-{sha1,sha224,sha256,sha384,sha512}`.
Output (r, s): base64-encoded concatenation of I2OSP of r and s, each of length
equal to the base point order in bytes (32 for P-256, 66 for P-521).

Required curve: P-256 (FIPS 186-3 §D.2.3). Recommended: P-384, P-521.

### Canonicalization

All algorithms take octet-stream or node-set, produce octet-stream output.
Output is UTF-8 (no BOM), NFC. See [XML-C14N], [XML-C14N11], [XML-EXC-C14N].

### Transforms

- **base64** (octet→octet, node-set→octet): decodes base64. For node-set input,
  logically applies `self::text()`, sorts by document order, concatenates.
- **XPath Filtering** (octet|node-set → node-set): evaluates XPath per node,
  includes nodes where boolean result is true. Includes `here()` function.
- **Enveloped Signature**: removes the containing `Signature` element from
  digest calculation. Equivalent to specific XPath.
- **XSLT**: octet-stream → octet-stream via XSL stylesheet (sole child).

## XML Canonicalization Considerations

Signatures only work if verification uses the same bits as signing. XML surface
forms vary, so canonicalization standardizes before signing/verification.

Categories of change to canonicalize:
1. XML 1.0 syntax (line endings, attribute defaults, entity refs, attribute
   normalization).
2. DOM/SAX information loss (attribute order, insignificant whitespace, namespace
   declaration locations).
3. Charset conversion.
4. Namespace inheritance/context.

All canonicalization algorithms identified use UTF-8 (no BOM) and do not perform
character normalization. Applications SHOULD produce content in NFC.

### Namespace Context and Portable Signatures

Inclusive canonicalization "attracts" ancestor namespace context, breaking
signatures when subdocuments are moved. Exclusive canonicalization "repels"
ancestor context, preserving portability.

## Security Considerations

### 8.1 Transforms

- Only what is signed is secure.
- Only what is "seen" should be signed.
- "See" what is signed (operate over canonicalized form).

### 8.2 Security Models

Public-key signatures vs keyed-hash MACs have different trust models. Public
keys verify; only private-key holders can sign. MAC keys are shared; any
verifier can forge.

### 8.3 Algorithms, Key Lengths, Certificates

Conforming implementations MUST support RSA signature generation and
verification with public keys at least 2048 bits. 3072-bit recommended for
signatures verified beyond 2030.

### 8.4 Error Messages

Generic error responses; avoid leaking specifics about algorithm processing.

## References

- [XML-C14N] Canonical XML 1.0
- [XML-C14N11] Canonical XML 1.1
- [XML-EXC-C14N] Exclusive XML Canonicalization 1.0
- [PKCS1] RFC 3447 (RSA Cryptography Specifications v2.1)
- [FIPS-186-3] Digital Signature Standard
- [FIPS-180-3] Secure Hash Standard
- [HMAC] RFC 2104
- [RFC6931] Additional XML Security URIs
- [XPATH] XML Path Language 1.0
- [XMLDSIG-BESTPRACTICES] XML Signature Best Practices
