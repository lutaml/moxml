# frozen_string_literal: true

module Moxml
  module XSD
    # Ruby-side post-validation rules closing the tier-1
    # under-detections tracked in #452: an engine may accept, inside
    # its recognized scope, instances that violate
    #
    #   * a strict `xs:any` wildcard with an undeclared element,
    #   * a strict `xs:anyAttribute` with an undeclared attribute,
    #   * `xsi:nil` on an element whose declaration is not nillable.
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

      # A wildcard's namespace attribute, per XML Schema
      # Structures §3.10.2 (##any default; processContents default
      # strict). :tns / :local are resolved against the indexed
      # schema at check time.
      class Wildcard
        def initialize(value, process)
          @process = (process || "strict").to_sym
          case value
          when nil, "##any", ""
            @mode = :any
          when "##other"
            @mode = :other
          else
            @mode = :list
            @namespaces = value.split(/\s+/).reject(&:empty?).freeze
          end
        end

        def strict?
          @process == :strict
        end

        def covers?(namespace)
          case @mode
          when :any then true
          when :other
            namespace != :local && namespace != :tns
          else
            @namespaces.any? { |entry| entry_covers?(entry, namespace) }
          end
        end

        private

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
              model.any ||= Wildcard.new(child["namespace"],
                                         child["processContents"])
            when "anyAttribute"
              model.any_attribute ||=
                Wildcard.new(child["namespace"],
                             child["processContents"])
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

        def child_findings(child, model, index)
          qname = qname(child)
          findings = []
          if model.declared_children.include?(qname)
            declaration = index.elements[qname]
            findings << nil_finding(child, declaration) if declaration
          elsif undeclared_strict_wildcard_match?(child, model, index,
                                                  qname)
            findings << Moxml::XSD::ValidationError.new(
              message: "element <#{local(qname)}> matches a strict " \
                       "wildcard but is not declared",
              path: path_of(child),
            )
          end
          findings.concat(
            attribute_findings(child, index.contents[qname], index),
          )
          findings
        end

        def undeclared_strict_wildcard_match?(_child, model, index, qname)
          wildcard = model.any
          return false unless wildcard&.strict?
          return false if index.elements.key?(qname)

          namespace = resolve_namespace(qname, index)
          wildcard.covers?(namespace) && !index.elements.key?(qname)
        end

        def attribute_findings(element, model, index)
          return [] unless model

          any_attribute = model.any_attribute
          element.attributes.filter_map do |attribute|
            next if attribute.namespace&.uri == XSI_NS

            qname = attribute_qname(attribute)
            declared = model.declared_attributes.include?(qname) ||
              index.attributes.key?(qname)
            next if declared
            next unless any_attribute&.strict?
            next if index.attributes.key?(qname)
            next unless any_attribute.covers?(
              resolve_namespace(qname, index),
            )

            Moxml::XSD::ValidationError.new(
              message: "attribute #{local(qname)} matches a strict " \
                       "wildcard but is not declared",
              path: path_of(element),
            )
          end
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
