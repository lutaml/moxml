# frozen_string_literal: true

module Moxml
  # Instantiation shells (issue #230): the node-type constants are
  # contract MODULES so leptris TypedData natives can carry them in
  # place — wrappers are minted through these shells for native
  # objects that cannot take the modules in place (binding-layer
  # natives on every adapter, and all natives on non-leptris ones).
  module Wrappers
    Node = Class.new do
      include Moxml::Node
    end
    Element = Class.new(Node) do
      include Moxml::Element
    end
    Text = Class.new(Node) do
      include Moxml::Text
    end
    Cdata = Class.new(Node) do
      include Moxml::Cdata
    end
    Comment = Class.new(Node) do
      include Moxml::Comment
    end
    ProcessingInstruction = Class.new(Node) do
      include Moxml::ProcessingInstruction
    end
    Document = Class.new(Node) do
      include Moxml::Document
    end
    Declaration = Class.new(Node) do
      include Moxml::Declaration
    end
    Doctype = Class.new(Node) do
      include Moxml::Doctype
    end
    Attribute = Class.new(Node) do
      include Moxml::Attribute
    end
    EntityReference = Class.new(Node) do
      include Moxml::EntityReference
    end
    Namespace = Class.new(Node) do
      include Moxml::Namespace
    end
  end
end
