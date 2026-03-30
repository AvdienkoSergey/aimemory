# ADR-001: LID Format (Logical ID)

**Status:** Accepted
**Date:** 2026-03-30

## Context

We need a way to identify code entities (components, functions, stores). Options:

1. **UUID** — `550e8400-e29b-41d4-a716-446655440000`
2. **File path** — `src/components/Button.vue`
3. **Semantic ID** — `comp:ui/Button`

Requirements:
- AI must understand the ID without looking in the database
- People must read the ID in logs easily
- ID must be stable when code changes inside a file

## Decision

Format is `kind:path` where:
- `kind` — entity type from a fixed set (`comp`, `fn`, `store`...)
- `path` — logical path, not tied to file system

```
comp:ui/Button        — Button component in ui module
fn:useAuth:login      — login function in useAuth composable
store:cart            — cart store
```

Code is in `lib/domain/lid.ml`:
- Type `kind` — OCaml variant with exhaustive matching
- Parsing with `of_string` with typed errors
- `Map` and `Set` for collections

## Results

### Good
- **Self-documenting:** `fn:auth/login` is clearer than UUID
- **Type safety:** invalid kind will not compile
- **Stable:** renaming file does not break ID if logic is same
- **Queryable:** can search by kind (`WHERE kind = 'fn'`)

### Bad
- **Manual assignment:** AI must create path itself (but this is also good — AI understands context)
- **Collisions:** two different Buttons in different modules need different paths

### Trade-offs
- Path is not checked for uniqueness on create — this is AI's job
- Kind set is fixed in code, adding new kinds needs changes to `lid.ml`
