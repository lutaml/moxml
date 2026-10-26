# frozen_string_literal: true

module Moxml
  module XSD
    # Ruby-side post-validation rules closing the tier-1
    # under-detections tracked in #452: an engine may accept, inside
    # its recognized scope, instances that violate
    #
    #   * a strict `xs:any` wildcard with an undeclared element,
    #   * a strict `xs:anyAttribute` with an undeclared attribute,
    #   * `xsi:nil` on an element whose declaration is not nillable,
    #   * the XSD 1.1 negative wildcards — `notQName` /
    #     `notNamespace` on `xs:any` / `xs:anyAttribute` (#460):
    #     engines that compile them without enforcing them absorb
    #     excluded items the content model cannot accept.
    #
    # The rules run from an index of the schema SOURCE (this gem's
    # own XML machinery — no engine involvement) and merge with the
    # engine's findings; exact duplicates are dropped. Findings are
    # one-directional: the index covers one schema document at
    # tier-1's one-level content depth, so a missing piece can only
    # under-report, never false-report — the same lax-scope posture
    # tier-1 already has.
    module SchemaRules
      XSI_NS = "http://www.w3.org/2001/XMLSchema-instance"

      # A wildcard's namespace constraint and disallowed names, per
      # XML Schema Structures §3.10.1–3.10.2 (##any default;
      # processContents default strict; notNamespace / notQName are
      # XSD 1.1). :tns / :local are resolved against the indexed
      # schema at check time; notQName QNames are resolved against
      # the schema element's in-scope bindings at index time.
      class Wildcard
        def initialize(value, process, not_namespace: nil, not_qname: nil,
                       element: nil)
          @process = (process || "strict").to_sym
          @mode, @namespaces = namespace_constraint(value, not_namespace)
          @disallowed = disallowed_names(not_qname, element).freeze
        end

        def strict?
          @process == :strict
        end

        def covers?(namespace)
          case @mode
          when :any then true
          when :other
            namespace != :local && namespace != :tns
          when :not
            @namespaces.none? { |entry| entry_covers?(entry, namespace) }
          else
            @namespaces.any? { |entry| entry_covers?(entry, namespace) }
          end
        end

        # Why the wildcard refuses an item outright (Structures
        # §3.10.4.1 Item Valid): a refusal is a match-level failure,
        # so it applies at every processContents — the content model
        # has no particle for the item and cannot accept it. 1.0
        # namespace lists stay the engine's enforcement and never
        # name an exclusion here.
        def negative_exclusion(qname, namespace, defined:,
                               sibling_names: [])
          @disallowed.each do |entry|
            case entry
            when :defined
              return :not_qname if defined
            when :sibling
              return :not_qname if sibling_names.include?(qname)
            else
              return :not_qname if entry == qname
            end
          end
          return :not_namespace if @mode == :not &&
            @namespaces.any? { |entry| entry_covers?(entry, namespace) }

          nil
        end

        private

        def namespace_constraint(value, not_namespace)
          if not_namespace
            [:not, not_namespace.split(/\s+/).reject(&:empty?)]
          elsif value.nil? || value == "##any" || value == ""
            [:any, []]
          elsif value == "##other"
            [:other, []]
          else
            [:list, value.split(/\s+/).reject(&:empty?)]
          end
        end

        # notQName entries (§3.10.2): QName | ##defined |
        # ##definedSibling (xs:any; ##defined only on
        # xs:anyAttribute). Prefixed QNames resolve against the
        # wildcard element's in-scope bindings; unprefixed QNames
        # carry no namespace — XSD QName values take no default
        # namespace. Unresolvable prefixes are dropped: the index
        # under-reports, never false-reports.
        def disallowed_names(not_qname, element)
          not_qname.to_s.split(/\s+/).reject(&:empty?).filter_map do |token|
            case token
            when "##defined" then :defined
            when "##definedSibling" then :sibling
            when /\A([^:]+):(.+)\z/
              uri = ::Moxml::XSD::SchemaRules.prefix_uri(
                Regexp.last_match(1), element
              )
              "{#{uri}}#{Regexp.last_match(2)}" unless uri.empty?
            else
              "{}#{token}"
            end
          end
        end

        def entry_covers?(entry, namespace)
          namespace == case entry
                       when "##targetNamespace" then :tns
                       when "##local" then :local
                       else entry
                       end
        end
      end

      ContentModel = Struct.new(:declared_children, :any,
                                :declared_attributes, :any_attribute,
                                :particles, :pure_sequence)
      SchemaIndex = Struct.new(:target_namespace, :element_default,
                               :attribute_default, :elements,
                               :attributes, :contents, :version,
                               :element_patterns, :attribute_patterns,
                               :substitution_members)

      # Resolves a QName token against an element's in-scope
      # bindings. node.namespaces is adapter-divergent (some
      # engines return in-scope bindings, others own-node
      # declarations only), so the in-scope map is walked out by
      # hand — per-node definitions merged along the ancestor
      # axis, deeper overriding shallower, identically on every
      # adapter. Unresolvable prefixes yield "".
      module_function

      def prefix_uri(prefix, element)
        bindings = {}
        node = element
        while node
          node.namespaces.each do |namespace|
            bindings[namespace.prefix] = namespace.uri
          end
          node = node.parent&.element? ? node.parent : nil
        end
        bindings[prefix].to_s
      end

      # The XSD 1.1 version-tagging namespace (Structures §C.3):
      # vc:minVersion / vc:maxVersion gate 1.1 constructs.
      VC_NS = "http://www.w3.org/2001/XMLSchema-versioning"

      # XSD pattern-facet dialect → Ruby regex, bounded to the
      # subset the facade vouches for (Datatypes Appendix F). Block
      # escapes \p{Is…}/\P{Is…} map to Ruby's In-prefixed blocks
      # (a few Unicode-renamed blocks carry an alias); general
      # categories and the single-character escapes pass through;
      # \i, \c and class subtraction are NOT translated. Anything
      # unrecognized — or a translation Ruby itself rejects —
      # returns nil: the engine's answer then stands.
      module XsdRegex
        BLOCK_ALIASES = {
          "Greek" => "GreekandCoptic",
          "CombiningMarksforSymbols" =>
            "CombiningDiacriticalMarksforSymbols",
          "Turkish" => "Latin-1Supplement",
        }.freeze

        PASS_THROUGH_ESCAPES = %w[
          n r t \\ . | ? * + ( ) [ ] { } ^ $ -
        ].freeze

        module_function

        def translate(pattern)
          translated = scan(pattern.to_s)
          return nil unless translated

          Regexp.new("\\A(?:#{translated})\\z")
        rescue RegexpError
          nil
        end

        def scan(pattern)
          out = +""
          index = 0
          while index < pattern.length
            char = pattern[index]
            if char == "\\"
              consumed = escape(pattern, index, out)
              return nil unless consumed

              index += consumed
            else
              return nil if char == "-" && pattern[index + 1] == "["

              out << char
              index += 1
            end
          end
          out
        end

        # Appends the translation of the escape at index to out and
        # returns the chars consumed, or nil when unrecognized.
        def escape(pattern, index, out)
          kind = pattern[index + 1]
          case kind
          when "p", "P"
            close = pattern.index("}", index)
            return nil unless close

            body = pattern[index + 3, close - index - 3]
            if body&.start_with?("Is")
              mapped = body.delete_prefix("Is")
              mapped = BLOCK_ALIASES.fetch(mapped, mapped)
              begin
                Regexp.new("\\p{In#{mapped}}")
              rescue RegexpError
                return nil
              end
              out << "\\#{kind}{In#{mapped}}"
            else
              out << pattern[index..close]
            end
            close - index + 1
          when *PASS_THROUGH_ESCAPES
            out << pattern[index, 2]
            2
          end
        end
      end

      class << self
        # Index one schema document. Returns nil when the source
        # cannot be indexed — the engine's answer then stands alone
        # (today's behavior).
        def index(schema_source, context)
          root = context.parse(schema_source).root
          return nil unless root&.name == "schema"

          index = SchemaIndex.new(
            root["targetNamespace"].to_s,
            root["elementFormDefault"] == "qualified",
            root["attributeFormDefault"] == "qualified",
            {}, {}, {}, schema_version(root), {}, {}, {}
          )
          child_elements(root).each do |decl|
            case decl.name
            when "element" then index_global_element(decl, index)
            when "attribute" then index_global_attribute(decl, index)
            end
          end
          index_patterns(root, index)
          index
        rescue StandardError
          nil
        end

        # The effective schema version declared at the root
        # (#460 item 2): vc:minVersion="1.1" on <xs:schema> scopes
        # the document to 1.1 semantics; anything else reports
        # 1.0. Conditional (subtree-level) vc: evaluation is the
        # engine's conditional-assignment work — the facade reports
        # the root declaration only.
        def schema_version(root)
          declared = root.attributes.find do |attribute|
            attribute.namespace&.uri == VC_NS &&
              attribute.name == "minVersion"
          end&.value
          declared.to_s.start_with?("1.1") ? "1.1" : "1.0"
        end

        # Index the pattern facets the dismissal may vouch with
        # (#464): named simpleTypes resolve through one type-ref
        # hop, inline simpleTypes directly; keys are local names.
        # A name declared twice with different pattern sets is
        # ambiguous for name-based matching and is removed — an
        # ambiguous vouch could mask a real violation.
        def index_patterns(root, index)
          named = {}
          collect_named_patterns(root, named)
          collect_decl_patterns(root, index, named)
        end

        def collect_named_patterns(node, named)
          child_elements(node).each do |child|
            if child.name == "simpleType" && child["name"] &&
                (patterns = restriction_patterns(child))
              named[child["name"]] = patterns
            else
              collect_named_patterns(child, named)
            end
          end
        end

        def collect_decl_patterns(node, index, named)
          child_elements(node).each do |child|
            case child.name
            when "element"
              register_pattern(index.element_patterns, child["name"],
                               decl_patterns(child, named))
            when "attribute"
              register_pattern(index.attribute_patterns, child["name"],
                               decl_patterns(child, named))
            end
            collect_decl_patterns(child, index, named)
          end
        end

        def decl_patterns(decl, named)
          inline = child_elements(decl).find do |child|
            child.name == "simpleType"
          end
          if inline
            restriction_patterns(inline)
          elsif decl["type"]
            named[decl["type"].split(":").last]
          end
        end

        def restriction_patterns(simple_type)
          restriction = child_elements(simple_type).find do |child|
            child.name == "restriction"
          end
          return nil unless restriction

          patterns = child_elements(restriction)
            .select { |facet| facet.name == "pattern" }
            .map { |facet| XsdRegex.translate(facet["value"].to_s) }
          return nil if patterns.any?(&:nil?)

          patterns
        end

        def register_pattern(sink, name, patterns)
          return unless name && patterns && !patterns.empty?

          sink[name] = sink.key?(name) ? nil : patterns
        end

        # Dismisses engine findings the schema source refutes:
        #
        # * lexical findings pattern facets accept (#464) — dropped
        #   only when every same-named instance matches the facet;
        # * content-model findings that reject a substitution-group
        #   member (#466 class 1) — dropped only when the parent's
        #   content model is a pure sequence, the child sequence
        #   matches it position-for-position with every particle
        #   exactly-once, and a substitution member resolves a
        #   position. One non-vouching instance — or any real
        #   mismatch — keeps the engine's answer, so a dismissal
        #   can only remove false rejections, never create false
        #   acceptances.
        def dismiss(engine_errors, doc, index)
          return engine_errors unless index

          vouched = vouch_table(doc, index)
          engine_errors.reject do |error|
            if (subject = lexical_subject(error.message))
              vouched[subject]
            elsif (sequence = content_model_subject(error.message))
              sequence_vouched?(doc, index, *sequence)
            end
          end
        end

        LEXICAL_MESSAGE = /\A(?:element|attribute) '([^']+)' @\d+:\d+: (element|attribute) '([^']+)': lexical value does not match its type\z/
        CONTENT_MODEL_MESSAGE = /\Aelement '([^']+)' @\d+:\d+: element '([^']+)': children do not match the content model \(at '([^']+)'\)\z/

        private_constant :LEXICAL_MESSAGE, :CONTENT_MODEL_MESSAGE

        def lexical_subject(message)
          match = LEXICAL_MESSAGE.match(message.to_s)
          return unless match

          [match[2], match[3]]
        end

        def content_model_subject(message)
          match = CONTENT_MODEL_MESSAGE.match(message.to_s)
          return unless match

          [match[2], match[3]]
        end

        # Every same-named element in the document must vouch: a
        # sequence the finding names could be valid while another
        # same-named one is not. The root is included — the
        # engine's finding can name it.
        def sequence_vouched?(doc, index, name, offender)
          root = doc.root
          return false unless root

          witnesses = []
          yield_self = root.name == name
          witnesses << sequence_valid?(root, index, offender) if yield_self
          each_named_element(root, name) do |element|
            witnesses << sequence_valid?(element, index, offender)
          end
          !witnesses.empty? && witnesses.all?
        end

        def each_named_element(node, name, &block)
          child_elements(node).each do |child|
            yield child if child.name == name
            each_named_element(child, name, &block)
          end
        end

        # The airtight witness: child count equals particle count,
        # every position resolves to its particle's name or a
        # registered member of it, every particle occurs exactly
        # once, and the reported offender is a substitution member
        # realized at some position. Anything else leaves the
        # engine's answer standing.
        def sequence_valid?(element, index, offender)
          model = index.contents[qname(element)]
          return false unless model&.pure_sequence

          particles = model.particles
          children = child_elements(element)
          return false if children.empty? || children.size != particles.size

          resolved = false
          children.each_with_index do |child, position|
            particle_name, min, max = particles[position]
            child_qname = qname(child)
            return false unless exactly_once?(min, max)

            if child_qname == particle_name
              next
            elsif index.substitution_members.fetch(particle_name, [])
                .include?(child_qname)
              resolved = true
            else
              return false
            end
          end
          resolved && offender_realized?(children, offender, index)
        end

        def exactly_once?(min, max)
          min <= 1 && (max == :unbounded || max >= 1)
        end

        def offender_realized?(children, offender, index)
          members = index.substitution_members.values.flatten
          children.any? do |child|
            child.name == offender &&
              members.include?(qname(child))
          end
        end

        def vouch_table(doc, index)
          root = doc.root
          return {} unless root

          elements = Hash.new { |hash, key| hash[key] = [] }
          attributes = Hash.new { |hash, key| hash[key] = [] }
          collect_witnesses(root, index, elements, attributes)
          vouched = {}
          elements.each do |name, matches|
            vouched[["element", name]] = !matches.empty? && matches.all?
          end
          attributes.each do |name, matches|
            vouched[["attribute", name]] = !matches.empty? && matches.all?
          end
          vouched
        end

        def collect_witnesses(node, index, elements, attributes)
          child_elements(node).each do |child|
            if (patterns = index.element_patterns[child.name])
              elements[child.name] << (text_only?(child) &&
                patterns.any? { |regex| regex.match?(child.text.to_s) })
            end
            child.attributes.each do |attribute|
              next if attribute.namespace&.uri == XSI_NS

              if (patterns = index.attribute_patterns[attribute.name])
                attributes[attribute.name] <<
                  patterns.any? { |regex| regex.match?(attribute.value.to_s) }
              end
            end
            collect_witnesses(child, index, elements, attributes)
          end
        end

        def text_only?(element)
          child_elements(element).empty?
        end

        # Post-validation findings for one instance document.
        def findings(doc, index)
          return [] unless index

          root = doc.root
          return [] unless root

          root_qname = qname(root)
          declaration = index.elements[root_qname]
          model = index.contents[root_qname]
          findings = []
          findings << nil_finding(root, declaration) if declaration
          findings.concat(attribute_findings(root, model, index))
          if model
            child_elements(root).each do |child|
              findings.concat(child_findings(child, model, index))
            end
          end
          findings.compact
        end

        private

        def index_global_element(decl, index)
          name = decl["name"] or return
          qname = "{#{index.target_namespace}}#{name}"
          index.elements[qname] = { nillable: decl["nillable"] == "true" }
          if (head = decl["substitutionGroup"])
            register_substitution(head, decl, qname, index)
          end
          type_attr = decl.attribute("type")
          model = if type_attr.nil? || type_attr.value.empty?
                    inline_model(decl, index)
                  else
                    named_model(decl, index)
                  end
          index.contents[qname] = model if model
        end

        # substitutionGroup is a QName resolved against the global
        # declaration's in-scope bindings (#466 class 1); the
        # member's own qname is target-namespace-qualified — global
        # declarations always are.
        def register_substitution(head, decl, member_qname, index)
          if head.include?(":")
            prefix, _, local = head.partition(":")
            uri = prefix_uri(prefix, decl)
            return if uri.empty?

            head_qname = "{#{uri}}#{local}"
          else
            head_qname = "{}#{head}"
          end
          (index.substitution_members[head_qname] ||= []) << member_qname
        end

        def index_global_attribute(decl, index)
          name = decl["name"] or return
          index.attributes["{#{index.target_namespace}}#{name}"] = true
        end

        def inline_model(decl, index)
          type_node = child_elements(decl).find do |child|
            child.name == "complexType"
          end
          content_model(type_node, index) if type_node
        end

        # A named complexType reference, indexed only when the
        # definition sits directly under this schema element.
        def named_model(decl, index)
          type_name = decl.attribute("type")&.value.to_s.split(":").last
          return nil unless type_name

          type_node = child_elements(decl.parent).find do |child|
            child.name == "complexType" && child["name"] == type_name
          end
          content_model(type_node, index) if type_node
        end

        def content_model(type_node, index)
          model = ContentModel.new([], nil, [], nil, [], true)
          collect_model(type_node, index, model)
          model
        end

        # Particle presence across the type's subtree (sequence /
        # choice / all / complexContent wrappers flattened): we only
        # ADD findings for strict-wildcard matches, so flattening
        # can only under-report, never over-report. Cardinality and
        # order stay the engine's job — EXCEPT for the substitution
        # dismissal (#466 class 1), which vouches only for pure
        # sequences: any choice/all marks the model impure and the
        # flattened order is then not a validity witness.
        def collect_model(node, index, model)
          child_elements(node).each do |child|
            case child.name
            when "element"
              if (qname = particle_qname(child, index))
                model.declared_children << qname
                model.particles << [
                  qname,
                  occur_value(child, "minOccurs", 1),
                  occur_value(child, "maxOccurs", 1),
                ]
              end
            when "attribute"
              if (qname = particle_qname(child, index))
                model.declared_attributes << qname
              end
            when "any"
              model.any ||= wildcard_from(child)
            when "anyAttribute"
              model.any_attribute ||= wildcard_from(child)
            when "choice", "all"
              model.pure_sequence = false
              collect_model(child, index, model)
            else
              collect_model(child, index, model)
            end
          end
        end

        def particle_qname(particle, index)
          ref = particle["ref"]
          name = ref&.split(":")&.last || particle["name"]
          return unless name

          if ref
            "{#{index.target_namespace}}#{name}"
          else
            "{#{form_namespace(particle, index)}}#{name}"
          end
        end

        def occur_value(particle, attribute, default)
          value = particle[attribute]
          return :unbounded if value == "unbounded"

          Integer(value || default)
        rescue ArgumentError
          default
        end

        # Particles declare with form="qualified"/"unqualified",
        # else the schema's elementFormDefault (elements) /
        # attributeFormDefault (attributes) — both default
        # unqualified.
        def form_namespace(particle, index)
          default = if particle.name == "element"
                      index.element_default
                    else
                      index.attribute_default
                    end
          case particle["form"]
          when "qualified" then index.target_namespace
          when "unqualified" then ""
          else default ? index.target_namespace : ""
          end
        end

        def wildcard_from(node)
          Wildcard.new(
            node["namespace"], node["processContents"],
            not_namespace: node["notNamespace"],
            not_qname: node["notQName"],
            element: node
          )
        end

        def child_findings(child, model, index)
          qname = qname(child)
          findings = []
          if model.declared_children.include?(qname)
            declaration = index.elements[qname]
            findings << nil_finding(child, declaration) if declaration
          elsif model.any &&
              (finding = wildcard_child_finding(child, model, index,
                                                qname))
            findings << finding
          end
          findings.concat(
            attribute_findings(child, index.contents[qname], index),
          )
          findings
        end

        def wildcard_child_finding(child, model, index, qname)
          wildcard = model.any
          namespace = resolve_namespace(qname, index)
          exclusion = wildcard.negative_exclusion(
            qname, namespace,
            defined: index.elements.key?(qname),
            sibling_names: model.declared_children
          )
          return excluded_child_finding(child, qname, exclusion) if exclusion

          return unless wildcard.covers?(namespace) && wildcard.strict?
          return if index.elements.key?(qname)

          Moxml::XSD::ValidationError.new(
            message: "element <#{local(qname)}> matches a strict " \
                     "wildcard but is not declared",
            path: path_of(child),
          )
        end

        def excluded_child_finding(child, qname, exclusion)
          reason = exclusion == :not_namespace ? "notNamespace" : "notQName"
          Moxml::XSD::ValidationError.new(
            message: "element <#{local(qname)}> is disallowed by a " \
                     "wildcard (#{reason}) and is not declared in the " \
                     "content model",
            path: path_of(child),
          )
        end

        def attribute_findings(element, model, index)
          return [] unless model

          any_attribute = model.any_attribute
          element.attributes.filter_map do |attribute|
            next if attribute.namespace&.uri == XSI_NS

            qname = attribute_qname(attribute)
            next if model.declared_attributes.include?(qname)
            next unless any_attribute

            namespace = resolve_namespace(qname, index)
            exclusion = any_attribute.negative_exclusion(
              qname, namespace,
              defined: index.attributes.key?(qname)
            )
            next excluded_attribute_finding(element, qname, exclusion) if exclusion

            next unless any_attribute.covers?(namespace)
            next unless any_attribute.strict?
            next if index.attributes.key?(qname)

            Moxml::XSD::ValidationError.new(
              message: "attribute #{local(qname)} matches a strict " \
                       "wildcard but is not declared",
              path: path_of(element),
            )
          end
        end

        def excluded_attribute_finding(element, qname, exclusion)
          reason = exclusion == :not_namespace ? "notNamespace" : "notQName"
          Moxml::XSD::ValidationError.new(
            message: "attribute #{local(qname)} is disallowed by a " \
                     "wildcard (#{reason}) and is not declared in the " \
                     "content model",
            path: path_of(element),
          )
        end

        def nil_finding(element, declaration)
          return if declaration[:nillable]

          value = element.attributes.find do |attribute|
            attribute.namespace&.uri == XSI_NS &&
              attribute.name == "nil"
          end&.value
          return unless %w[true 1].include?(value)

          Moxml::XSD::ValidationError.new(
            message: "element <#{element.name}> is not nillable but " \
                     "carries xsi:nil=\"#{value}\"",
            path: path_of(element),
          )
        end

        # {uri}local → the wildcard vocabulary: :tns when the
        # namespace is the schema's target, :local when empty, the
        # URI otherwise.
        def resolve_namespace(qname, index)
          namespace = namespace_of(qname)
          if namespace.empty?
            :local
          elsif namespace == index.target_namespace
            :tns
          else
            namespace
          end
        end

        def qname(node)
          "{#{node.namespace&.uri}}#{node.name}"
        end

        def attribute_qname(attribute)
          "{#{attribute.namespace&.uri}}#{attribute.name}"
        end

        def namespace_of(qname)
          qname[/^\{(.*)\}/, 1].to_s
        end

        def local(qname)
          qname[/\}(.*)$/, 1].to_s
        end

        def child_elements(node)
          node.children.select(&:element?)
        end

        def path_of(node)
          segments = [node.name]
          current = node
          while (parent = current.parent)&.element?
            segments.unshift(parent.name)
            current = parent
          end
          segments.join("/")
        end
      end
    end
  end
end
