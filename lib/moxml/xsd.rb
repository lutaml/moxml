# frozen_string_literal: true

module Moxml
  # XSD validation. Implementation-agnostic over engines that ship
  # an XSD validator (currently leptris, tier-1: named+typed
  # top-level elements, one-level content-model descent, lexical
  # builtin/simpleType checks — see docs/c14n for the sibling
  # pattern). Beside the engine, SchemaRules re-checks strict
  # wildcards and xsi:nil from the schema source on every adapter —
  # engines that miss those shapes stay model-conformant, and
  # engines that already detect them get no duplicate findings.
  #
  #     ctx    = Moxml.new(:leptris)
  #     schema = ctx.xsd(<<~XSD)
  #       <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
  #         <xs:element name="note" type="t_note"/>
  #         <xs:complexType name="t_note">
  #           <xs:sequence>
  #             <xs:element name="to" type="xs:string"/>
  #           </xs:sequence>
  #         </xs:complexType>
  #       </xs:schema>
  #     XSD
  #     schema.valid?(doc)     # => true/false
  #     schema.validate(doc)   # => [] or [ValidationError(...)]
  #
  # Adapters without an engine raise Moxml::NotImplementedError at
  # compile; Moxml::XSD.supported?(context) answers without
  # raising. The tier-1 scope is the engine's: documents outside it
  # validate laxly, except for the re-checked shapes above (which
  # can only under-report, never false-report).
  module XSD
    SUPPORTED_ADAPTERS = %i[leptris nokogiri].freeze

    autoload :SchemaRules, "moxml/xsd/schema_rules"
    autoload :BuiltinLexical, "moxml/xsd/builtin_lexical"

    # One validation finding, harmonized across adapters (#362.2):
    # +message+ always present; +line+ / +column+ when the engine
    # reports them; +path+ (the element path) when the engine
    # reports it — nil where the payload lacks the datum rather
    # than a guessed placeholder. #to_s preserves the plain-string
    # consumer flows the pre-#362 string contract fed.
    class ValidationError
      attr_reader :message, :line, :column, :path

      def initialize(message:, line: nil, column: nil, path: nil)
        @message = message.to_s
        @line = line
        @column = column
        @path = path
      end

      def to_s
        if line
          "#{line}: #{message}"
        else
          message
        end
      end

      def ==(other)
        other.is_a?(ValidationError) &&
          message == other.message && line == other.line &&
          column == other.column && path == other.path
      end
    end

    class << self
      # Whether the context's adapter ships an XSD validator.
      # Answers without raising; compile raises
      # Moxml::NotImplementedError regardless (the capability probe
      # is advisory).
      def supported?(context)
        adapter = context.config.adapter
        adapter.const_defined?(:XSD_SUPPORTED) &&
          adapter.const_get(:XSD_SUPPORTED)
      end

      # Lexical validation against the facade-owned built-in type
      # table (the "xs:NAME" reference spelling). One committed
      # answer on every adapter (#482); raises ArgumentError when
      # the name is not in the table.
      def builtin_valid?(_context, builtin, lexical)
        BuiltinLexical.valid?(builtin, lexical)
      end
    end

    # A compiled schema (adapter-owned handle). Validation results
    # are the engine's accumulated messages; [] means valid.
    class Schema
      def check_released!
        return unless released?

        raise Moxml::AdapterError,
              "schema released (deterministic drop); compile a new one"
      end

      def initialize(handle, context, schema_source = nil,
                     self_contained: nil, path: nil)
        @handle = handle
        @context = context
        @schema_path = path
        @rules_index =
          if schema_source
            SchemaRules.index(schema_source, context,
                              self_contained: self_contained)
          end
        assert_adapter_matches_handle!
      end

      # Issue #384: the handle is an adapter-native object; routing
      # it through a different adapter's xsd_validate surfaced as a
      # distant NoMethodError. Fail at the wrap with the mismatch
      # named.
      def assert_adapter_matches_handle!
        adapter = @context.config.adapter
        return if adapter.xsd_handle_match?(@handle)

        raise Moxml::AdapterError.new(
          "schema handle mismatch: #{handle_class_name(@handle)} " \
          "cannot be validated through the " \
          "#{adapter.respond_to?(:adapter_name) ? adapter.adapter_name : adapter} " \
          "adapter — compile the schema through the same adapter " \
          "that will validate it",
          operation: "xsd_compile",
        )
      end

      def handle_class_name(handle)
        handle.class.name.split("::").last(2).join("::")
      end

      # Validate a node or raw XML string. Returns [] when valid.
      # FROZEN string sources parse once and are memoized for the
      # schema's lifetime — re-validating the same document is the
      # hot consumer shape, and a per-call parse costs the full
      # document pool every time (moxml#350's MB-per-validate
      # growth). Unfrozen strings re-parse (mutation must be
      # visible); pass a Moxml::Document to control the parse
      # yourself.
      def validate(node_or_xml)
        check_released!
        doc = case node_or_xml
              when Moxml::Document then node_or_xml
              when Moxml::Node then node_or_xml.document
              else
                cached = @parsed_source
                if cached && node_or_xml.frozen? &&
                    cached[0].equal?(node_or_xml)
                  cached[1]
                else
                  parsed = @context.parse(node_or_xml.to_s)
                  if node_or_xml.frozen?
                    @parsed_source = [node_or_xml, parsed]
                  end
                  parsed
                end
              end
        engine_errors = @context.config.adapter.xsd_validate(
          validation_handle(doc), doc.native
        )
        engine_errors = dismiss_refuted_not_declared(engine_errors, doc)
        return engine_errors unless @rules_index

        # The #452 post-validation rules only ever add findings for
        # documents the engine accepted; the #464 dismissal removes
        # only engine lexical findings the source's own pattern
        # facets refute. Exact duplicates are dropped for engines
        # that already detect them.
        (SchemaRules.dismiss(engine_errors, doc, @rules_index) +
          SchemaRules.findings(doc, @rules_index)).uniq
      end

      # Validations run against the compile-time handle. The
      # composition fix (#522) is dismissal-side: the facade indexes
      # every unit of the composition (the schema + the instance's
      # xsi:schemaLocation hints) and drops engine strict-admission
      # rows the index refutes — engines whose admission consults
      # only the head unit's declarations never see the aux units,
      # and recompiling a mixed-targetNamespace union would swap one
      # false answer for another.
      def validation_handle(_doc)
        @handle
      end

      XSI_NS = "http://www.w3.org/2001/XMLSchema-instance"

      # xsi:schemaLocation (namespace/path pairs) and
      # xsi:noNamespaceSchemaLocation paths from the validated
      # instance's root, resolved against this schema's directory
      # and filtered to files that exist. Empty when this schema was
      # compiled from a string (no base to resolve against).
      def instance_schema_hints(doc)
        return [].freeze unless @schema_path
        return [].freeze unless doc&.root

        base = File.dirname(@schema_path)
        root = doc.root
        hints = []
        root.attributes.each do |attribute|
          next unless attribute.namespace&.uri == XSI_NS

          value = attribute.value.to_s
          case attribute.name
          when "noNamespaceSchemaLocation"
            hints << value
          when "schemaLocation"
            hints.concat(value.split(/\s+/).reject(&:empty?)
              .each_slice(2).map(&:last))
          end
        end
        hints.uniq
          .map { |hint| File.expand_path(hint, base) }
          .select do |p|
            File.file?(p) && p != File.expand_path(@schema_path)
          end.freeze
      end

      # Engine strict-admission rows the composed unit set REFUTES:
      # engines whose wildcard admission consults only the head
      # unit's declaration table report "attribute 'x': not declared
      # (strict)" for attributes declared in another unit of the
      # same compiled composition, and the mixed-tns fresh union
      # compile itself can mis-admit a root element the same way
      # (leptris#1964 family, moxml#522). The facade owns the
      # composition, so it can refute a row when the named item, as
      # it appears in THIS instance, is a global declaration of any
      # unit (namespace + local name). Only exact "not declared
      # (strict)" rows are ever dropped; every other engine finding
      # passes through untouched.
      def dismiss_refuted_not_declared(engine_errors, doc)
        return engine_errors if engine_errors.empty? || !@schema_path

        hints = instance_schema_hints(doc)
        units = composed_unit_set([@schema_path, *hints])
        declared = composed_declarations(units)
        admissible = element_admissibility(units)
        return engine_errors if declared.empty? && admissible.empty?

        attr_index = {}
        element_ns = {}
        stack = [doc.root]
        while (element = stack.pop)
          element_ns[(element.namespace&.uri || "")] ||= true
          stack.concat(element.children.grep(Moxml::Element))
          element.attributes.each do |attribute|
            attr_uri = attribute.namespace&.uri || ""
            ((attr_index[[attr_uri, attribute.name]] ||= []) <<
              element.name)
          end
        end
        engine_errors.reject do |finding|
          match = NOT_DECLARED_ROW.match(finding.message)
          next false unless match

          element_name = match[1]
          attribute_name = match[2]
          if attribute_name
            attr_index.any? do |(uri, attr_name), holders|
              next false unless attr_name == attribute_name &&
                holders.include?(element_name)

              # A global declaration of some unit, or a group member
              # the element's type admits (moxml#522 attgC class —
              # exact (element, attribute, namespace) match).
              declared.key?([uri, attribute_name]) ||
                admissible.dig(element_name, attribute_name) == uri
            end
          else
            declared.key?(["", element_name]) ||
              (element_ns[element_name] &&
                declared.key?([element_ns[element_name], element_name]))
          end
        end
      end

      # The composition closure of the unit set: every unit's
      # xs:include / xs:import / xs:redefine schemaLocation targets
      # (existing files), cycle-guarded, resolved relative to each
      # unit. The engine compiles these documents as ONE composition;
      # the facade's index must see the same set even when the
      # instance carries no xsi hints (attgC035's redefined groups
      # live in documents only the schema graph knows).
      def composed_unit_set(units)
        @composed_unit_set ||= {}
        cached = @composed_unit_set[units]
        return cached if cached

        seen = {}
        queue = units.dup
        until queue.empty?
          unit = queue.pop
          next if seen.key?(unit)

          seen[unit] = true
          base = File.dirname(unit)
          unit_schema_refs(unit).each do |ref|
            target = File.expand_path(ref, base)
            queue << target if File.file?(target) && !seen.key?(target)
          end
        end
        closure = seen.keys.sort
        @composed_unit_set[units] = closure
        closure
      end

      # schemaLocation hrefs on the unit's own xs:include, xs:import
      # and xs:redefine (poison-immune REXML read; the engine's
      # component tables are process-global and a later parse can
      # poison compiled handles, moxml#522).
      def unit_schema_refs(unit)
        require "rexml/document"
        root = REXML::Document.new(File.read(unit)).root
        return [].freeze unless root&.name == "schema"

        refs = %w[include import redefine].map do |tag|
          root.elements.each_with_object([]) do |node, out|
            next unless node.name == tag

            loc = node.attributes["schemaLocation"]
            out << loc if loc.to_s.match?(/\S/)
          end
        end.flatten
        refs.freeze
      rescue StandardError
        [].freeze
      end

      # {element name => {attribute name => namespace}}: every
      # attribute the composition admits for each element — the
      # element's type's attributeGroup members resolved transitively
      # across units (import groups; an xs:redefine body's self-ref
      # is the 4.2.2 hook to the ORIGINAL definition, so the
      # effective group is body UNION original). Only exact members
      # of the real composition land here, so a genuinely undeclared
      # attribute never becomes refutable.
      def element_admissibility(units)
        @element_admissibility ||= {}
        cached = @element_admissibility[units]
        return cached if cached

        facts = {}
        units.each do |unit|
          unit_facts = schema_unit_facts(unit)
          facts[unit] = unit_facts if unit_facts
        end

        # Effective group definitions: redefining bodies merge the
        # target unit's original when (and only when) the body hooks
        # it with a self-ref. Keys: bare name AND {uri}name (refs
        # resolve with the referencing unit's xmlns, bare-name
        # fallback — same-name groups are composition-unique).
        plain = {}
        bodies = {}
        facts.each_value do |unit|
          unit[:redefines].each do |name, target_path|
            body = unit[:groups][name]
            original = facts[target_path]&.dig(:groups, name)
            bodies[name] = merge_group_def(body, original, name)
          end
          unit[:groups].each do |name, defn|
            plain[name] = defn unless unit[:redefines].key?(name)
          end
        end
        # Redefine bodies are the EFFECTIVE definitions — they win
        # over the plain originals.
        groups = plain.merge(bodies)

        resolved = {}
        facts.each_value do |unit|
          unit[:elements].each do |element_name, element|
            attrs = {}
            element[:groups].each do |qref|
              resolve_group_ref(qref, unit, groups, attrs, {})
            end
            element[:attrs].each do |name, uri|
              attrs[name] = uri
            end
            resolved[element_name] = attrs unless attrs.empty?
          end
        end
        @element_admissibility[units] = resolved.freeze
      end

      # body UNION original when the body hooks the original with a
      # self-ref; the body alone otherwise.
      def merge_group_def(body, original, name)
        return body unless body && original.is_a?(Hash) &&
          body[:refs].include?(name)

        {
          attrs: body[:attrs] + original[:attrs],
          refs: body[:refs] + original[:refs],
        }
      end

      # Resolve one attributeGroup ref (raw QName string) into attrs
      # {name => uri}, transitively; cycle-guarded by +seen+. Keys
      # are bare names with qualified "{uri}name" fallbacks.
      def resolve_group_ref(qref, from_unit, groups, attrs, seen)
        return if seen.key?(qref)

        seen[qref] = true
        prefix, _, local = qref.rpartition(":")
        xmlns = from_unit[:xmlns]
        uri = if prefix.empty?
                xmlns["xmlns"].to_s
              else
                xmlns["xmlns:#{prefix}"].to_s
              end
        defn = groups["{#{uri}}#{local}"] || groups[local]
        return unless defn.is_a?(Hash)

        defn[:attrs].each do |name, attr_uri|
          attrs[name] = attr_uri
        end
        defn[:refs].each do |ref|
          resolve_group_ref(ref, from_unit, groups, attrs, seen)
        end
      end

      # Per-unit schema facts for the admissibility index:
      # {tns, afd (attributeFormDefault qualified?), xmlns,
      #  groups: {name => {attrs, refs}}, redefines: {name => target},
      #  elements: {name => {groups, attrs}}} — poison-immune REXML.
      # Attribute member URIs use the DEFINING unit's form rules;
      # group refs stay raw QNames (resolved at chase time).
      def schema_unit_facts(unit)
        require "rexml/document"
        root = REXML::Document.new(File.read(unit)).root
        return nil unless root&.name == "schema"

        xmlns = {}
        root.attributes.each do |name, value|
          xmlns[name] = value.to_s if name.start_with?("xmlns")
        end
        tns = root.attributes["targetNamespace"].to_s
        afd = root.attributes["attributeFormDefault"] == "qualified"

        member_uri = lambda do |node|
          qualified = node.attributes["form"] == "qualified" || afd
          qualified ? tns : ""
        end

        groups = {}
        redefines = {}
        root.elements.each do |node|
          case node.name
          when "attributeGroup"
            name = node.attributes["name"]
            next unless name

            groups[name] = walk_group_members(node, member_uri)
          when "redefine"
            loc = node.attributes["schemaLocation"]
            node.elements.each do |body|
              next unless body.name == "attributeGroup"

              name = body.attributes["name"]
              next unless name

              groups[name] = walk_group_members(body, member_uri)
              redefines[name] = File.expand_path(loc, File.dirname(unit)) if
                loc.to_s.match?(/\S/)
            end
          end
        end

        elements = {}
        root.elements.each do |node|
          next unless node.name == "element"
          next unless (name = node.attributes["name"])

          container = node.elements.find { |child| child.name == "complexType" }
          type_name = node.attributes["type"].to_s
          container ||= root.elements.find do |child|
            child.name == "complexType" && child.attributes["name"] == type_name
          end
          next unless container.is_a?(REXML::Element)

          groups_seen, attrs = walk_type_attributes(container, member_uri)
          elements[name] = { groups: groups_seen, attrs: attrs }
        end

        {
          tns: tns, afd: afd, xmlns: xmlns, groups: groups,
          redefines: redefines, elements: elements
        }
      rescue StandardError
        nil
      end

      # Refs and attribute members of one attributeGroup definition.
      # Refs stay raw QNames — the chase resolves prefixes through
      # the referencing unit's xmlns.
      def walk_group_members(node, member_uri)
        refs = []
        attrs = []
        node.elements.each do |child|
          case child.name
          when "attribute"
            name = child.attributes["name"]
            attrs << [name, member_uri.call(child)] if name
          when "attributeGroup"
            ref = child.attributes["ref"]
            refs << ref if ref.to_s.match?(/\S/)
          end
        end
        { attrs: attrs, refs: refs }
      end

      # attributeGroup refs + own attribute members of a complexType
      # (one level; nested group-through-group chains resolve at
      # chase time). Returns [raw refs, attrs].
      def walk_type_attributes(container, member_uri)
        refs = []
        attrs = []
        container.elements.each do |child|
          case child.name
          when "attributeGroup"
            ref = child.attributes["ref"]
            refs << ref if ref.to_s.match?(/\S/)
          when "attribute"
            name = child.attributes["name"]
            attrs << [name, member_uri.call(child)] if name
          end
        end
        [refs, attrs]
      end

      # {uri, local} => true for every global xs:attribute and
      # xs:element declared across the unit set: a global
      # declaration always takes its unit's targetNamespace.
      # Parsed with REXML when available: the engine's component
      # tables are process-global and can be poisoned by later
      # parses between compile and validate (moxml#522) — a
      # declaration index must be poison-immune. Falls back to the
      # context parse when REXML is unavailable.
      def composed_declarations(units)
        @composed_declarations ||= {}
        cached = @composed_declarations[units]
        return cached if cached

        declared = {}
        parser = begin
          require "rexml"
          :rexml
        rescue LoadError
          :context
        end
        units.each do |unit|
          tns, decls = unit_declarations(unit, parser)
          next unless decls

          decls.each do |name|
            declared[[tns, name]] = true
          end
        end
        @composed_declarations[units] = declared
      end

      # [targetNamespace, [global attribute/element names]] for one
      # schema unit, per the parser flavor. REXML's read is
      # poison-immune; the context parse is the fallback.
      def unit_declarations(unit, parser)
        text = File.read(unit)
        if parser == :rexml
          require "rexml/document"
          root = REXML::Document.new(text).root
          return nil unless root&.name == "schema"

          tns = root.attributes["targetNamespace"].to_s
          names = %w[attribute element].freeze
          decls = root.elements.filter_map do |decl|
            next unless names.include?(decl.name)

            decl.attributes["name"]
          end
        else
          root = @context.parse(text).root
          return nil unless root&.name == "schema"

          tns = root.attributes.find { |a| a.name == "targetNamespace" }
            &.value.to_s
          names = %w[attribute element].freeze
          decls = root.children
            .grep(Moxml::Element)
            .filter_map do |decl|
              next unless names.include?(decl.name)

              decl.attributes.find { |a| a.name == "name" }&.value
            end
        end
        [tns, decls]
      rescue StandardError
        nil
      end

      # Matches both row shapes the strict admission emits — with and
      # without the attribute segment:
      #   element 'doc' @2:144: element 'doc': not declared (strict)
      #   element 'elem' @3:46: attribute 'foo': not declared (strict)
      NOT_DECLARED_ROW =
        /\Aelement '([^']+)'(?: @\S+)? (?:(?:element|attribute) '([^']+)': )?not declared \(strict\)\z/

      def valid?(node_or_xml)
        check_released!
        validate(node_or_xml).empty?
      end

      # Number of top-level schema declarations the compiler
      # recognized.
      def declarations
        check_released!
        @context.config.adapter.xsd_declarations(@handle)
      end

      # The effective schema version (#460 item 2): "1.1" or
      # "1.0". The engine's answer (root @version) can only
      # UPGRADE to 1.1 — it never downgrades the source-derived
      # answer, because vc:minVersion="1.1" selects 1.1 semantics
      # even when @version is absent, and @version="1.1" alongside
      # vc:minVersion="1.0" is an authoring contradiction the
      # source annotation wins.
      def version
        adapter = @context.config.adapter
        engine = if adapter.respond_to?(:xsd_version)
                   adapter.xsd_version(@handle)
                 end
        return "1.1" if engine == "1.1"

        @rules_index ? @rules_index.version : "1.0"
      end

      # One row per engine finding with the structured fields the
      # #1843 report carries (moxml#460): kind, component, line,
      # column, message. Nil when the binding predates the face —
      # callers keep using #validate/#errors for the flat shape.
      EngineFinding = Struct.new(:kind, :component, :line, :column,
                                 :message)

      def structured_errors(node_or_xml)
        check_released!
        doc = case node_or_xml
              when Moxml::Document then node_or_xml
              when Moxml::Node then node_or_xml.document
              else @context.parse(node_or_xml.to_s)
              end
        adapter = @context.config.adapter
        rows = if adapter.respond_to?(:xsd_structured_errors)
                 adapter.xsd_structured_errors(@handle, doc.native)
               end
        return nil unless rows

        rows.map do |r|
          EngineFinding.new(r.kind, r.component, r.line, r.column,
                            r.message)
        end
      end

      # Deterministic drop (#362.3): true when the adapter freed
      # the engine-side schema NOW; false when the adapter can only
      # wait for GC (documented per adapter). After a true release
      # the faces raise AdapterError — the handle is gone.
      def release
        dropped = @context.config.adapter.xsd_release(@handle)
        @released = true if dropped
        dropped
      end

      def released?
        @released == true
      end

      # The engine's schema-level compile error, or nil when the
      # schema compiled cleanly.
      def compile_error
        check_released!
        @context.config.adapter.xsd_compile_error(@handle)
      end

      # Lexical validation of +lexical+ against the schema's user
      # simpleType +type_name+. Unknown type names raise.
      def simple_valid?(type_name, lexical)
        @context.config.adapter.xsd_simple_valid?(
          @handle, type_name, lexical
        )
      end

      # Content-model check for one element's children. +children+
      # are Moxml nodes (names + effective namespaces are read
      # engine-side). Unknown element names raise.
      def content_valid?(element_name, children)
        @context.config.adapter.xsd_content_valid?(
          @handle, element_name, children
        )
      end
    end
  end
end
