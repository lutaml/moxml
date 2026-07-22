# XML Signature Best Practices

W3C Working Group Note 11 April 2013

- This version: http://www.w3.org/TR/2013/NOTE-xmldsig-bestpractices-20130411/
- Latest published version: http://www.w3.org/TR/xmldsig-bestpractices/
- Latest editor's draft: http://www.w3.org/2008/xmlsec/Drafts/best-practices/Overview.html
- Previous version: http://www.w3.org/TR/2013/NOTE-xmldsig-bestpractices-20130124/
- Editors: Frederick Hirsch (Nokia), Pratik Datta (Oracle)

Copyright © 2013 W3C® (MIT, ERCIM, Keio, Beihang), All Rights Reserved.

## Abstract

This document collects best practices for implementers and users of the XML
Signature specification [XMLDSIG-CORE1]. Most of these best practices are
related to improving security and mitigating attacks, yet others are for best
practices in the practical use of XML Signature, such as signing XML that
doesn't use namespaces, for example.

## 1. Overview

The XML Signature specification [XMLDSIG-CORE1] offers powerful and flexible
mechanisms to support a variety of use cases. This flexibility has the downside
of increasing the number of possible attacks. One countermeasure to the
increased number of threats is to follow best practices, including a
simplification of use of XML Signature where possible.

## 2. Best Practices for Implementers

### 2.1 Reduce the opportunities for denial of service attacks

XML Signature may be used in application server systems, where multiple incoming
messages are being processed simultaneously. In this situation incoming messages
should be assumed to be possibly hostile with the concern that a single poison
message could bring down an entire set of web applications and services.

**Best Practice 1**: Mitigate denial of service attacks by executing potentially
dangerous operations only after successfully authenticating the signature.

Validate the `ds:Reference` elements for a signature only after establishing
trust, for example by verifying the key and validating `ds:SignedInfo` first.

Recommended order of operations:

1. **Step 1** — fetch the verification key and establish trust in that key.
2. **Step 2** — validate `ds:SignedInfo` with that key.
3. **Step 3** — validate the references.

**Best Practice 2**: Establish trust in the verification/validation key (validate
X.509 certificates, certificate chains and revocation status).

#### 2.1.1 XSLT transform that causes denial of service

A nested-loop XSLT can require O(N^4) operations on a document with N elements.

**Best Practice 3**: Consider avoiding XSLT Transforms.

#### 2.1.2 XSLT transform that executes arbitrary code

XSLT user-defined extensions can execute arbitrary code (e.g., shell commands).

**Best Practice 4**: When XSLT is required disallow the use of user-defined
extensions.

#### 2.1.3 XPath Filtering transform that causes denial of service

A document with N namespaces and N elements produces N×N namespace nodes; an
XPath Filter evaluates the expression once per node, giving O(N^4) cost.

**Best Practice 5**: Try to avoid or limit XPath transforms.

#### 2.1.4 XPath selection DoS in streaming mode

Wildcard axes (descendant, following, etc.) cause search-context explosion in
streaming verifiers.

**Best Practice 6**: Avoid using "descendant", "descendant-or-self",
"following-sibling", and "following" axes when using streaming XPaths.

#### 2.1.5 Retrieval method that causes an infinite loop

`ds:RetrievalMethod` may form cyclic references.

**Best Practice 7**: Try to avoid or limit `ds:RetrievalMethod` support with
`ds:KeyInfo`.

#### 2.1.6 Problematic external references

External URI references can read sensitive files or trigger side effects on
other sites.

**Best Practice 8**: Control external references (mitigate query parameters,
unknown URI schemes, inappropriate content).

#### 2.1.7 Denial of service caused by too many transforms

A reference may carry thousands of C14N transforms.

**Best Practice 9**: Limit the number of `ds:Reference` transforms allowed.

### 2.2 Provide a mechanism to determine what was signed

**Best Practice 10**: Offer interfaces for the application to learn what was
signed (return pre-digested data and pre-C14N data).

### 2.3 Be aware of certificate encoding issues

**Best Practice 11**: Do not re-encode certificates; use DER when possible with
the `X509Certificate` element. Re-encoding can break the signature on the
certificate.

## 3. Best Practices for Applications

### 3.1 Check what is signed

**Best Practice 12**: Enable verifier to automate "see what is signed"
functionality.

**Best Practice 13**: When applying XML Signatures using XPath it is recommended
to always actively verify that the signature protects the intended elements and
not more or less.

**Best Practice 14**: When checking a reference URI, don't just check the name of
the element (wrapping attack mitigation — also check position).

### 3.2 Prevent replay attacks

**Best Practice 15**: Unless impractical, sign all parts of the document.

**Best Practice 16**: Use a nonce in combination with signing time.

**Best Practice 17**: Do not rely on application logic to prevent replay attacks
since applications may change.

**Best Practice 18**: Nonce and signing time must be signature protected.

### 3.3 Enable Long-Lived Signatures

**Best Practice 19**: Use Timestamp tokens issued by Timestamp authorities for
long lived signatures.

**Best Practice 20**: Long lived signatures should include a `xsd:dateTime` field
to indicate the time of signing.

### 3.4 Signing XML without namespace information ("legacy XML")

**Best Practice 21**: When creating an enveloping signature over XML without
namespace information, take steps to avoid having that content inherit the XML
Signature namespace (insert an empty default namespace declaration, or define a
namespace prefix for the Signature namespace).

### 3.5 Prefer the XPath Filter 2 Transform

**Best Practice 22**: Prefer the XPath Filter 2 Transform to the XPath Filter
Transform if possible.

## 4. Best Practices for Signers and Verifiers

### 4.1 Do not transmit external unparsed entity references

**Best Practice 23**: Do not transmit unparsed external entity references in
signed material. Expand all entity references before creating the cleartext.

### 4.2 Be aware of schema processing

**Best Practice 24**: Do not rely on a validating processor on the consumer's end
to normalize XML documents.

**Best Practice 25**: Avoid destructive validation before signature validation.

### 4.3 HMAC truncation

**Best Practice 26**: When using an HMAC, set the HMAC Output Length to one half
the number of bits in the hash size.

### 4.4 Distinct keys for sign and encrypt

**Best Practice 27**: When encrypting and signing use distinct keys.

## 5. Best Practices Summary

1. Mitigate DoS by authenticating before dangerous operations.
2. Establish trust in the verification key.
3. Avoid XSLT transforms.
4. Disallow XSLT user-defined extensions.
5. Avoid/limit XPath transforms.
6. Avoid wildcard axes in streaming XPaths.
7. Avoid/limit `ds:RetrievalMethod`.
8. Control external references.
9. Limit number of transforms per Reference.
10. Offer interfaces to learn what was signed.
11. Don't re-encode certificates; prefer DER.
12. Enable verifier to "see what is signed".
13. With XPath, verify the signature actually protects intended elements.
14. When checking reference URI, check both name and position.
15. Sign all parts of the document unless impractical.
16. Use nonce + signing time.
17. Don't rely solely on application logic for replay prevention.
18. Nonce and signing time must be signature protected.
19. Use TSA-issued timestamp tokens for long-lived signatures.
20. Include `xsd:dateTime` for signing time in long-lived signatures.
21. Avoid namespace inheritance in enveloping signatures over legacy XML.
22. Prefer XPath Filter 2 over XPath Filter.
23. Don't transmit unparsed external entity references.
24. Don't rely on validating parser on consumer's end.
25. Avoid destructive validation before signature validation.
26. Truncate HMAC to half hash size.
27. Use distinct keys for signing and encryption.

## References

- [XMLDSIG-CORE1] — XML Signature Syntax and Processing Version 1.1
- [XADES] — XML Advanced Electronic Signatures (ETSI TS 101 903)
- [RFC3161] — Internet X.509 PKI Time-Stamp Protocol (TSP)
- [MCINTOSH-WRAP] — XML signature element wrapping attacks and countermeasures
