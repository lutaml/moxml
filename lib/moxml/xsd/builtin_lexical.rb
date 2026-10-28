# frozen_string_literal: true

module Moxml
  module XSD
    # Facade-owned lexical validation for the XSD built-in simple
    # types (Datatypes Part 2). One committed answer for every
    # adapter: engines with their own tables converge to this one,
    # never the reverse (#482). The check is lexical only — pattern,
    # enumeration and other constraining facets belong to the
    # schema, not to the built-in's own space.
    module BuiltinLexical
      module_function

      # Answers for the "xs:NAME" reference spelling. Unknown names
      # raise ArgumentError — the facade never guesses.
      def valid?(builtin, lexical)
        checker = CHECKERS.fetch(builtin) do
          raise ArgumentError, "unknown built-in type #{builtin.inspect}"
        end

        checker.call(lexical.to_s)
      end

      # XML 1.0 5th ed. name productions. NCName excludes ":";
      # xs:Name and xs:NMTOKEN admit it.
      NCNAME_START_CLASS =
        "A-Z_a-z\u{C0}-\u{D6}\u{D8}-\u{F6}\u{F8}-\u{2FF}\u{370}-\u{37D}" \
        "\u{37F}-\u{1FFF}\u{200C}-\u{200D}\u{2070}-\u{218F}\u{2C00}-\u{2FEF}" \
        "\u{3001}-\u{D7FF}\u{F900}-\u{FDCF}\u{FDF0}-\u{FFFD}"
      NCNAME_CHAR_CLASS =
        "#{NCNAME_START_CLASS}0-9.\\-\u{B7}\u{300}-\u{36F}\u{203F}-\u{2040}".freeze

      NCNAME = /\A[#{NCNAME_START_CLASS}][#{NCNAME_CHAR_CLASS}]*\z/
      NAME = /\A[:#{NCNAME_START_CLASS}][:#{NCNAME_CHAR_CLASS}]*\z/
      NMTOKEN = /\A[:#{NCNAME_CHAR_CLASS}]+\z/

      INTEGER_LEXICAL = /\A[+-]?[0-9]+\z/
      DECIMAL_LEXICAL = /\A[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)\z/
      FLOAT_LEXICAL = /\A(?:[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[Ee][+-]?[0-9]+)?|[+-]?INF|NaN)\z/
      BOOLEAN_LEXICAL = /\A(?:true|false|0|1)\z/
      LANGUAGE_LEXICAL = /\A[A-Za-z]{1,8}(?:-[A-Za-z0-9]{1,8})*\z/
      HEX_LEXICAL = /\A(?:[0-9A-Fa-f]{2})*\z/
      BASE64_LEXICAL = /\A(?:[A-Za-z0-9+\/]{4})*(?:[A-Za-z0-9+\/]{2}==|[A-Za-z0-9+\/]{3}=)?\z/

      DATE_PART = /-?(?:[1-9][0-9]{3,}|0[0-9]{3})-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12][0-9]|3[01])/
      TIME_PART = /(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](?:\.[0-9]+)?/
      ZONE = /(?:Z|[+-](?:0[0-9]|1[0-3]):[0-5][0-9]|14:00)/
      DATE_LEXICAL = /\A#{DATE_PART}#{ZONE}?\z/
      TIME_LEXICAL = /\A#{TIME_PART}#{ZONE}?\z/
      DATE_TIME_LEXICAL = /\A#{DATE_PART}T#{TIME_PART}#{ZONE}?\z/
      DATE_TIME_STAMP_LEXICAL = /\A#{DATE_PART}T#{TIME_PART}#{ZONE}\z/
      G_YEAR_LEXICAL = /\A-?(?:[1-9][0-9]{3,}|0[0-9]{3})#{ZONE}?\z/
      G_YEAR_MONTH_LEXICAL = /\A-?(?:[1-9][0-9]{3,}|0[0-9]{3})-(?:0[1-9]|1[0-2])#{ZONE}?\z/
      G_MONTH_LEXICAL = /\A--(?:0[1-9]|1[0-2])#{ZONE}?\z/
      G_DAY_LEXICAL = /\A---(?:0[1-9]|[12][0-9]|3[01])#{ZONE}?\z/
      G_MONTH_DAY_LEXICAL = /\A--(?:0[1-9]|1[0-2])-(?:0[1-9]|[12][0-9]|3[01])#{ZONE}?\z/
      DURATION_LEXICAL = /\A-?P(?:[0-9]+Y)?(?:[0-9]+M)?(?:[0-9]+D)?(?:T(?:[0-9]+H)?(?:[0-9]+M)?(?:[0-9]+(?:\.[0-9]+)?S)?)?\z/

      MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze

      private_constant :NCNAME_START_CLASS, :NCNAME_CHAR_CLASS, :NCNAME,
                       :NAME, :NMTOKEN, :INTEGER_LEXICAL, :DECIMAL_LEXICAL,
                       :FLOAT_LEXICAL, :BOOLEAN_LEXICAL, :LANGUAGE_LEXICAL,
                       :HEX_LEXICAL, :BASE64_LEXICAL, :DATE_PART,
                       :TIME_PART, :ZONE, :DATE_LEXICAL, :TIME_LEXICAL,
                       :DATE_TIME_LEXICAL, :DATE_TIME_STAMP_LEXICAL,
                       :G_YEAR_LEXICAL, :G_YEAR_MONTH_LEXICAL,
                       :G_MONTH_LEXICAL, :G_DAY_LEXICAL,
                       :G_MONTH_DAY_LEXICAL, :DURATION_LEXICAL, :MONTH_DAYS

      # whiteSpace=collapse, shared by token and its derivatives.
      def collapsed(lexical)
        lexical.gsub(/[ \t\r\n]+/, " ").strip
      end

      def ncname?(lexical)
        NCNAME.match?(lexical)
      end

      # A QName is an optional NCName prefix, a colon, and an NCName
      # local part. The "xmlns" prefix is reserved (Namespaces in
      # XML) and never a legal QName prefix.
      def qname?(lexical)
        prefix, colon, local = lexical.partition(":")
        return ncname?(lexical) if colon.empty?

        return false if prefix == "xmlns"

        ncname?(prefix) && ncname?(local)
      end

      # List lexical spaces are whitespace-separated items, at least
      # one; every item must be a valid item-type lexical.
      def list?(lexical, &block)
        items = lexical.split(/[ \t\r\n]+/).reject(&:empty?)
        !items.empty? && items.all?(&block)
      end

      # The grammar admits a bare "T" and the empty body; the
      # lexical space requires at least one component, and a "T"
      # must be followed by one.
      def duration?(lexical)
        return false unless DURATION_LEXICAL.match?(lexical)

        body = lexical.sub(/\A-?P/, "")
        if (time_at = body.index("T"))
          /[0-9]/.match?(body[(time_at + 1)..].to_s)
        else
          /[0-9]/.match?(body)
        end
      end

      def day_time_duration?(lexical)
        return false unless duration?(lexical)

        head = lexical.split("T", 2).first.to_s
        !/[0-9]+[YM]/.match?(head)
      end

      def year_month_duration?(lexical)
        duration?(lexical) && !/[0-9]+D/.match?(lexical) &&
          !lexical.include?("T")
      end

      def leap_year?(year)
        ((year % 4).zero? && !(year % 100).zero?) || (year % 400).zero?
      end

      # Dates carry calendar validity in their lexical space: the
      # day must exist for the month and year (Gregorian, leap
      # rules on the absolute year).
      def calendar_date?(year, month, day)
        return false unless month.between?(1, 12)

        limit = MONTH_DAYS[month - 1]
        limit += 1 if month == 2 && leap_year?(year.abs)
        day.between?(1, limit)
      end

      def date_fields(lexical)
        match = /\A(-?[0-9]{4,})-([0-9]{2})-([0-9]{2})/.match(lexical)
        return unless match

        match.captures.map { |field| Integer(field) }
      end

      def with_date_fields(lexical)
        year, month, day = date_fields(lexical)
        year && yield(year, month, day)
      end

      def integer?(lexical, range: nil)
        return false unless INTEGER_LEXICAL.match?(lexical)

        range.nil? || range.cover?(Integer(lexical))
      end

      def signed(range)
        ->(lexical) { integer?(lexical, range: range) }
      end

      private_class_method :collapsed, :ncname?, :qname?, :list?,
                           :duration?, :day_time_duration?,
                           :year_month_duration?, :leap_year?,
                           :calendar_date?, :date_fields,
                           :with_date_fields, :integer?, :signed

      CHECKERS = {
        "xs:anySimpleType" => ->(_lexical) { true },
        "xs:anyAtomicType" => ->(_lexical) { true },
        "xs:anyType" => ->(_lexical) { true },
        "xs:string" => ->(_lexical) { true },
        "xs:normalizedString" => ->(_lexical) { true },
        "xs:token" => ->(_lexical) { true },
        "xs:language" => ->(lexical) { LANGUAGE_LEXICAL.match?(collapsed(lexical)) },
        "xs:Name" => ->(lexical) { NAME.match?(collapsed(lexical)) },
        "xs:NCName" => ->(lexical) { ncname?(collapsed(lexical)) },
        "xs:ID" => ->(lexical) { ncname?(collapsed(lexical)) },
        "xs:IDREF" => ->(lexical) { ncname?(collapsed(lexical)) },
        "xs:ENTITY" => ->(lexical) { ncname?(collapsed(lexical)) },
        "xs:NMTOKEN" => ->(lexical) { NMTOKEN.match?(collapsed(lexical)) },
        "xs:IDREFS" => ->(lexical) { list?(lexical) { |item| ncname?(item) } },
        "xs:ENTITIES" => ->(lexical) { list?(lexical) { |item| ncname?(item) } },
        "xs:NMTOKENS" => ->(lexical) { list?(lexical) { |item| NMTOKEN.match?(item) } },
        "xs:boolean" => ->(lexical) { BOOLEAN_LEXICAL.match?(lexical) },
        "xs:decimal" => ->(lexical) { DECIMAL_LEXICAL.match?(lexical) },
        "xs:precisionDecimal" => ->(lexical) { FLOAT_LEXICAL.match?(lexical) },
        "xs:float" => ->(lexical) { FLOAT_LEXICAL.match?(lexical) },
        "xs:double" => ->(lexical) { FLOAT_LEXICAL.match?(lexical) },
        "xs:integer" => ->(lexical) { integer?(lexical) },
        "xs:nonPositiveInteger" => signed(-Float::INFINITY..0),
        "xs:negativeInteger" => signed(-Float::INFINITY...0),
        "xs:long" => signed(-(2**63)..((2**63) - 1)),
        "xs:int" => signed(-(2**31)..((2**31) - 1)),
        "xs:short" => signed(-32_768..32_767),
        "xs:byte" => signed(-128..127),
        "xs:nonNegativeInteger" => signed(0..Float::INFINITY),
        "xs:positiveInteger" => signed(1..Float::INFINITY),
        "xs:unsignedLong" => signed(0..((2**64) - 1)),
        "xs:unsignedInt" => signed(0..((2**32) - 1)),
        "xs:unsignedShort" => signed(0..65_535),
        "xs:unsignedByte" => signed(0..255),
        "xs:duration" => ->(lexical) { duration?(lexical) },
        "xs:dayTimeDuration" => ->(lexical) { day_time_duration?(lexical) },
        "xs:yearMonthDuration" => ->(lexical) { year_month_duration?(lexical) },
        "xs:dateTime" => ->(lexical) do
          with_date_fields(lexical) do |y, m, d|
            DATE_TIME_LEXICAL.match?(lexical) && calendar_date?(y, m, d)
          end
        end,
        "xs:dateTimeStamp" => ->(lexical) do
          with_date_fields(lexical) do |y, m, d|
            DATE_TIME_STAMP_LEXICAL.match?(lexical) && calendar_date?(y, m, d)
          end
        end,
        "xs:time" => ->(lexical) { TIME_LEXICAL.match?(lexical) },
        "xs:date" => ->(lexical) do
          with_date_fields(lexical) do |y, m, d|
            DATE_LEXICAL.match?(lexical) && calendar_date?(y, m, d)
          end
        end,
        "xs:gYear" => ->(lexical) { G_YEAR_LEXICAL.match?(lexical) },
        "xs:gYearMonth" => ->(lexical) do
          G_YEAR_MONTH_LEXICAL.match?(lexical) &&
            with_date_fields("#{lexical.sub(/(?:Z|[+-][0-9]{2}:[0-9]{2})\z/, '')}-01") do |y, m, d|
              calendar_date?(y, m, d)
            end
        end,
        "xs:gMonth" => ->(lexical) { G_MONTH_LEXICAL.match?(lexical) },
        "xs:gDay" => ->(lexical) { G_DAY_LEXICAL.match?(lexical) },
        "xs:gMonthDay" => ->(lexical) do
          match = /\A--([0-9]{2})-([0-9]{2})/.match(lexical)
          next false unless match

          month = Integer(match[1])
          limit = MONTH_DAYS[month - 1]
          limit += 1 if month == 2
          G_MONTH_DAY_LEXICAL.match?(lexical) &&
            Integer(match[2]).between?(1, limit)
        end,
        "xs:hexBinary" => ->(lexical) { HEX_LEXICAL.match?(lexical) },
        "xs:base64Binary" => ->(lexical) { BASE64_LEXICAL.match?(lexical.delete(" \t\r\n")) },
        "xs:anyURI" => ->(_lexical) { true },
        "xs:QName" => ->(lexical) { qname?(collapsed(lexical)) },
        "xs:NOTATION" => ->(lexical) { qname?(collapsed(lexical)) },
      }.freeze

      private_constant :CHECKERS
    end
  end
end
