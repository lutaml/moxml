# frozen_string_literal: true

module Moxml
  # The XSD-structural conformance family (#490 item 8, family 7):
  # single-file schema + instance pairs — namespace-aligned admission
  # shapes (builtin lexical, strict wildcard with a global in the
  # target namespace, substitution groups, lax ##other wildcards).
  # Every row's verdict is verified identical on both primary engines
  # through `Context#xsd_file`. Schemas are compact single-line
  # documents (whitespace-insensitive to the compiler); instances use
  # explicit prefixes because attribute defaults never qualify.
  # Multi-file composition shapes (imports, redefines) stay in the
  # W3C corpus lanes — these rows are deliberately self-contained for
  # the cross-language runners.
  module XsdStructuralCases
    XSD_LEXICAL =
      '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t" xmlns="urn:t"><xs:element name="doc"><xs:complexType><xs:sequence><xs:element name="n" type="xs:int"/><xs:element name="flag" type="xs:boolean"/></xs:sequence><xs:attribute name="a" type="xs:string"/><xs:anyAttribute namespace="##any" processContents="strict"/></xs:complexType></xs:element><xs:attribute name="ext" type="xs:string"/></xs:schema>'
    XSD_SUBS =
      '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:s" xmlns="urn:s"><xs:element name="shape" type="xs:string" abstract="true"/><xs:element name="circle" type="xs:string" substitutionGroup="shape"/><xs:element name="canvas"><xs:complexType><xs:sequence><xs:element ref="shape" maxOccurs="unbounded"/></xs:sequence></xs:complexType></xs:element></xs:schema>'
    XSD_WILDCARD =
      '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t" xmlns="urn:t"><xs:element name="doc"><xs:complexType><xs:sequence><xs:any processContents="lax" namespace="##other"/></xs:sequence></xs:complexType></xs:element></xs:schema>'

    CONFORMANCE_CASES = [
      ["builtin-lexical-valid", XSD_LEXICAL,
       '<d:doc xmlns:d="urn:t" a="x"><n>42</n><flag>true</flag></d:doc>',
       true],
      ["builtin-lexical-invalid", XSD_LEXICAL,
       '<d:doc xmlns:d="urn:t" a="x"><n>not-an-int</n><flag>true</flag></d:doc>',
       false],
      ["strict-admission-declared", XSD_LEXICAL,
       '<d:doc xmlns:d="urn:t" xmlns:t="urn:t" t:ext="y" a="x"><n>1</n><flag>false</flag></d:doc>',
       true],
      ["strict-admission-undeclared", XSD_LEXICAL,
       '<d:doc xmlns:d="urn:t" ghost="z" a="x"><n>1</n><flag>false</flag></d:doc>',
       false],
      ["substitution-member", XSD_SUBS,
       '<s:canvas xmlns:s="urn:s"><s:circle>unit</s:circle></s:canvas>',
       true],
      ["wildcard-lax-other-ns", XSD_WILDCARD,
       '<d:doc xmlns:d="urn:t" xmlns:o="urn:o"><o:kid/></d:doc>',
       true],
    ].map(&:freeze).freeze
  end
end
