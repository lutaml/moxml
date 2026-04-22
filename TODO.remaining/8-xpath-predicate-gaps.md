# TODO 8: XPath Engine Predicate Gaps (5 xit Tests)

## Problem

The pure-Ruby XPath engine (used by HeadedOx) does not fully support
`position()`, `last()`, and `id()` inside predicates. Five tests are marked
`xit` pending predicate support.

These gaps affect the XPath engine in `lib/moxml/xpath/` — they are not
adapter-specific.

## Failing Tests

### `position()` in Predicates (2 tests)

`spec/moxml/xpath/functions/position_functions_spec.rb`

```ruby
xit "returns current position in predicate" do
  # /root/item[position() = 2]
end

xit "works with position comparison" do
  # /root/item[position() > 1]
end
```

### `last()` in Predicates (2 tests)

`spec/moxml/xpath/functions/position_functions_spec.rb`

```ruby
xit "returns size of context in predicate" do
  # /root/item[position() = last()]
end

xit "works with last() - 1" do
  # /root/item[position() = last() - 1]
end
```

### `id()` with Nodeset Argument (1 test)

`spec/moxml/xpath/functions/special_functions_spec.rb:69`

```ruby
xit "accepts nodeset argument containing IDs" do
  # id(nodeset) where nodeset is path-evaluated
end
```

## Investigation Needed

- The XPath compiler likely needs to pass predicate context (position, size)
  into the evaluation environment when compiling predicate expressions.
- `position()` and `last()` are defined but raise `InvalidContextError` when
  used inside predicates — the predicate evaluation path doesn't set up the
  context they need.
- `id()` with a nodeset argument requires evaluating the argument as an XPath
  path first, then extracting ID values from the resulting nodes.

## Files

- `lib/moxml/xpath/compiler.rb` — predicate compilation
- `lib/moxml/xpath/engine.rb` — runtime evaluation context
- `lib/moxml/xpath/context.rb` — context setup for position/last
- `spec/moxml/xpath/functions/position_functions_spec.rb`
- `spec/moxml/xpath/functions/special_functions_spec.rb`
