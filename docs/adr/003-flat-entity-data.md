# ADR-003: Flat Structure for entity.data

**Status:** Accepted
**Date:** 2026-03-30

## Context

Entity stores data about code element. Options for structure:

1. **Any JSON:** nested objects, arrays of objects
2. **Flat JSON:** only primitives and arrays of primitives
3. **Schema:** fixed fields for each kind

## Decision

Flat structure: `Entity.data` is a list of pairs `(string * value)` where `value`:

```ocaml
type value =
  | String of string
  | Int of int
  | Float of float
  | Bool of bool
  | List of value list  (* only primitives *)
  | Null
```

Nested objects are not supported. If you need nesting — create separate entity with ref.

```
Bad:
{ "lid": "comp:Form",
  "data": { "fields": [{"name": "email", "type": "string"}] } }

Good:
{ "lid": "comp:Form", "data": {} }
{ "lid": "prop:Form:email", "data": {"type": "string"},
  "refs": [{"target": "comp:Form", "rel": "belongs_to"}] }
```

## Results

### Good
- **Queryable:** all data is on one level, easy to search
- **Normalization:** no duplication, everything is connected via refs
- **Simplicity:** parsing is trivial, no recursive structures

### Bad
- **Verbose:** more entities for complex structures
- **AI burden:** AI must split nested data

### Trade-offs
- Arrays of primitives are allowed (`tags: ["ui", "form"]`) — this is useful and keeps flatness
- Nested object in JSON is converted to string (fallback, not recommended)
