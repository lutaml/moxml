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
              uri = prefix_uri(Regexp.last_match(1), element)
              "{#{uri}}#{Regexp.last_match(2)}" unless uri.empty?
            else
              "{}#{token}"
            end
          end
        end

        # node.namespaces is adapter-divergent (some engines return
        # in-scope bindings, others own-node declarations only), so
        # the in-scope map is walked out by hand — per-node
        # definitions merged along the ancestor axis, deeper
        # overriding shallower, identically on every adapter.
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

        def entry_covers?(entry, namespace)
          namespace == case entry
                       when "##targetNamespace" then :tns
                       when "##local" then :local
                       else entry
                       end
        end
      end

      ContentModel = Struct.new(:declared_children, :any,
                                :declared_attributes, :any_attribute)
      SchemaIndex = Struct.new(:target_namespace, :element_default,
                               :attribute_default, :elements,
                               :attributes, :contents, :version)

      # The XSD 1.1 version-tagging namespace (Structures §C.3):
      # vc:minVersion / vc:maxVersion gate 1.1 constructs.
      VC_NS = "http://www.w3.org/2001/XMLSchema-versioning"

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
            {}, {}, {}, schema_version(root)
          )
          child_elements(root).each do |decl|
            case decl.name
            when "element" then index_global_element(decl, index)
            when "attribute" then index_global_attribute(decl, index)
            end
          end
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
          type_attr = decl.attribute("type")
          model = if type_attr.nil? || type_attr.value.empty?
                    inline_model(decl, index)
                  else
                    named_model(decl, index)
                  end
          index.contents[qname] = model if model
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
          model = ContentModel.new([], nil, [], nil)
          collect_model(type_node, index, model)
          model
        end

        # Particle presence across the type's subtree (sequence /
        # choice / all / complexContent wrappers flattened): we only
        # ADD findings for strict-wildcard matches, so flattening
        # can only under-report, never over-report. Cardinality and
        # order stay the engine's job.
        def collect_model(node, index, model)
          child_elements(node).each do |child|
            case child.name
            when "element"
              add_particle(child, index, model,
                           model.declared_children)
            when "attribute"
              add_particle(child, index, model,
                           model.declared_attributes)
            when "any"
              model.any ||= wildcard_from(child)
            when "anyAttribute"
              model.any_attribute ||= wildcard_from(child)
            else
              collect_model(child, index, model)
            end
          end
        end

        def add_particle(particle, index, _model, sink)
          ref = particle["ref"]
          name = ref&.split(":")&.last || particle["name"]
          return unless name

          sink << if ref
                    "{#{index.target_namespace}}#{name}"
                  else
                    "{#{form_namespace(particle, index)}}#{name}"
                  end
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
