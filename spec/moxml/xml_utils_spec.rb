# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::XmlUtils do
  # XmlUtils is a mixin module, create a test class that includes it
  let(:test_class) do
    Class.new do
      include Moxml::XmlUtils
    end
  end
  let(:utils) { test_class.new }

  describe "#validate_declaration_version" do
    it "validates XML versions" do
      expect { utils.validate_declaration_version("1.0") }.not_to raise_error
      expect { utils.validate_declaration_version("1.1") }.not_to raise_error
    end

    it "raises error for invalid version" do
      expect do
        utils.validate_declaration_version("2.0")
      end.to raise_error(Moxml::ValidationError, "Invalid XML version: 2.0")
    end
  end

  describe "#validate_declaration_encoding" do
    it "validates encodings" do
      expect { utils.validate_declaration_encoding("UTF-8") }.not_to raise_error
      expect do
        utils.validate_declaration_encoding("ISO-8859-1")
      end.not_to raise_error
    end
  end

  describe "#validate_element_name" do
    it "validates element names" do
      expect { utils.validate_element_name("root") }.not_to raise_error
      expect { utils.validate_element_name("my-element") }.not_to raise_error
    end

    it "raises error for invalid names" do
      expect do
        utils.validate_element_name("123invalid")
      end.to raise_error(Moxml::ValidationError,
                         "Invalid XML element name: 123invalid")
    end
  end
end
