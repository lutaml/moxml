# frozen_string_literal: true

module Moxml
  # CSS selector -> XPath 1.0 translation (#362.1): the shared
  # implementation behind Node#css/at_css. One translator for
  # every adapter — CSS semantics converge by construction instead
  # of per-engine differences. Supported: type/universal, #id,
  # .class, attribute predicates ([a], [a=v], ^=, $=, *=, ~=, |=),
  # the descendant/child/adjacent-sibling/following-sibling
  # combinators, :first-child/:last-child/:nth-child(n|odd|even),
  # :not(simple), and comma groups (union NodeSets).
  module Css
    class Error < Moxml::Error; end

    SIMPLE_PART = /
      (?<tag>^[A-Za-z][\w-]*|\*)
      | \.(?<class>[\w-]+)
      | \#(?<id>[\w-]+)
      | :(?<pseudo>[\w-]+(?:\([^)]*\))?)
      | \[(?<attr>[^\]]+)\]
    /x

    module_function

    # absolute: true when the context node is a DOCUMENT — the
    # "//" anchor addresses the whole tree (and avoids engines
    # that resolve "." at a document node to the root element);
    # false (an element) scopes to the subtree with ".//".
    def to_xpath(selector, absolute: false)
      selectors = split_top_level(selector.to_s)
      raise Error, "empty selector" if selectors.empty?

      anchor = absolute ? "" : "."
      selectors.map { |s| "#{anchor}#{to_xpath_one(s.strip)}" }
        .uniq.join(" | ")
    end

    # Bracket- and quote-aware tokenization: combinator characters
    # only split OUTSIDE [...] (a ~= inside an attribute selector
    # is not the sibling combinator).
    def tokenize(selector)
      tokens = []
      current = +""
      depth = 0
      quote = nil
      flush = lambda do
        unless current.empty?
          tokens << [:simple, current]
          current = +""
        end
      end
      selector.each_char do |c|
        if quote
          current << c
          quote = nil if c == quote
        elsif ["'", '"'].include?(c)
          quote = c
          current << c
        elsif c == "[" || c == "]" || depth.positive?
          depth += 1 if c == "["
          depth -= 1 if c == "]"
          current << c
        elsif c.match?(/[\s>+~]/)
          flush.call
          if tokens.last && tokens.last[0] == :comb
            # a concrete combinator replaces the whitespace run;
            # extra whitespace after one collapses
            if c.match?(/[>+~]/)
              tokens[-1] = [:comb, c]
            end
            next
          end
          tokens << [:comb, c.strip.empty? ? " " : c]
        elsif c == ","
          flush.call
          tokens << [:comma, ","]
        else
          current << c
        end
      end
      flush.call
      tokens
    end

    def to_xpath_one(selector)
      xpath = ""
      seen_step = false
      pending_combinator = :descendant

      tokenize(selector).each do |kind, value|
        if kind == :comb
          raise Error, "selector starts with a combinator" unless seen_step

          pending_combinator =
            case value.strip
            when ">" then :child
            when "+" then :adjacent
            when "~" then :sibling
            else :descendant
            end
        elsif kind == :comma
          raise Error, "trailing comma"
        else
          step = simple_selector_to_xpath(value, pending_combinator)
          sep = if !seen_step
                  pending_combinator == :descendant ? "//" : "/"
                elsif pending_combinator == :descendant
                  "//"
                else
                  "/"
                end
          xpath = "#{xpath}#{sep}#{step}"
          seen_step = true
          pending_combinator = :descendant
        end
      end

      raise Error, "selector ends with a combinator" if
        seen_step && pending_combinator != :descendant
      raise Error, "empty selector" unless seen_step

      xpath
    end

    def simple_selector_to_xpath(simple, combinator)
      tag, preds = parse_simple(simple)

      predicate = preds.empty? ? "" : "[#{preds.join(' and ')}]"

      case combinator
      when :adjacent
        # The FIRST following sibling, constrained to the test +
        # predicates (the CSS + semantics) — one combined
        # predicate, which oga's XPath subset parses (chained
        # [1][self::x] it does not).
        combined = (["position() = 1", "name() = '#{tag}'"] +
                    (preds.empty? ? [] : [preds.join(" and ")]))
          .join(" and ")
        "following-sibling::*[#{combined}]"
      when :sibling
        "following-sibling::#{tag}#{predicate}"
      else
        "#{tag}#{predicate}"
      end
    end

    def parse_simple(simple)
      tag = "*"
      preds = []

      simple.scan(SIMPLE_PART) do |tag_m, klass, id, pseudo, attr|
        if tag_m
          tag = tag_m
        elsif klass
          preds << "contains(concat(' ', normalize-space(@class), ' '), ' #{klass} ')"
        elsif id
          preds << "@id = '#{id}'"
        elsif pseudo
          preds << pseudo_predicate(pseudo)
        elsif attr
          preds << attr_predicate(attr)
        end
      end

      [tag, preds]
    end

    def pseudo_predicate(pseudo)
      case pseudo
      when "first-child"
        "count(preceding-sibling::*) = 0"
      when "last-child"
        "count(following-sibling::*) = 0"
      when /\Anth-child\((\d+)\)\z/
        "count(preceding-sibling::*) = #{Regexp.last_match(1).to_i - 1}"
      when /\Anth-child\(odd\)\z/i
        "count(preceding-sibling::*) mod 2 = 0"
      when /\Anth-child\(even\)\z/i
        "count(preceding-sibling::*) mod 2 = 1"
      when /\Anot\((.+)\)\z/
        inner = Regexp.last_match(1).strip
        negate(inner)
      else
        raise Error, "unsupported pseudo :#{pseudo}"
      end
    end

    def negate(inner_selector)
      raise Error, ":not supports a single simple selector" if
        inner_selector.match?(/[\s>+~,]/)

      tag, preds = parse_simple(inner_selector)
      return "false()" if tag == "*" && preds.empty?

      checks = []
      checks << "not(self::#{tag})" unless tag == "*"
      checks.concat(preds.map { |p| "not(#{p})" })
      "(#{checks.join(' and ')})"
    end

    def attr_predicate(expr)
      # Linear string parsing — CodeQL rb/polynomial-redos flags
      # the equivalent greedy regex (optional groups + .*\z
      # backtrack polynomially on adversarial input).
      expr = expr.strip
      name = expr[/\A[\w:-]+/]
      raise Error, "bad attribute selector: [#{expr}]" unless name

      rest = expr[name.length..].to_s.strip
      op = rest[/\A[~^$*|]?=/]
      value = (op ? rest[op.length..] : "").to_s.strip
      # No-backreference unquote (CodeQL rb/polynomial-redos: the
      # ('(["']).*\1\z shape backtracks polynomially).
      if value.length > 1 &&
          ((value.start_with?("'") && value.end_with?("'")) ||
           (value.start_with?('"') && value.end_with?('"')))
        value = value[1..-2]
      end
      literal = xpath_string_literal(value)

      case op
      when nil, "" then "@#{name}"
      when "=" then "@#{name} = #{literal}"
      when "^=" then "starts-with(@#{name}, #{literal})"
      when "$=" then "substring(@#{name}, string-length(@#{name}) - string-length(#{literal}) + 1) = #{literal}"
      when "*=" then "contains(@#{name}, #{literal})"
      when "~=" then "contains(concat(' ', normalize-space(@#{name}), ' '), concat(' ', #{literal}, ' '))"
      when "|=" then "@#{name} = #{literal} or starts-with(@#{name}, concat(#{literal}, '-'))"
      else raise Error, "unsupported attribute operator #{op}"
      end
    end

    # An XPath 1.0 string literal: values containing apostrophes
    # cannot escape the delimiter — they go through concat().
    def xpath_string_literal(value)
      return "'#{value}'" unless value.include?("'")

      parts = value.split("'", -1).map { |seg| "'#{seg}'" }
      "concat(#{parts.join(%(, "'", ))})"
    end

    def split_top_level(selector)
      out = []
      depth = 0
      quote = nil
      current = +""
      selector.each_char do |c|
        if quote
          current << c
          quote = nil if c == quote
        elsif ["'", '"'].include?(c)
          quote = c
          current << c
        elsif c == "["
          depth += 1
          current << c
        elsif c == "]"
          depth -= 1
          raise Error, "unbalanced ]" if depth.negative?

          current << c
        elsif c == "," && depth.zero?
          out << current
          current = +""
        else
          current << c
        end
      end
      raise Error, "unbalanced [" if depth.positive?

      out << current
      out.map(&:strip).reject(&:empty?)
    end
  end
end
