# ADR-006: Typed Errors

**Status:** Accepted
**Date:** 2026-03-30

## Context

System talks to AI via JSON. Errors happen: invalid LID, DB problems, unknown command. Options:

1. **Exceptions:** `raise Invalid_lid`
2. **String errors:** `Error "invalid lid"`
3. **Typed errors:** `Error (Invalid_lid (s, parse_error))`

## Decision

Typed errors at each level:

```ocaml
(* lid.ml *)
type parse_error =
  | Empty | Missing_colon | Unknown_kind of string | Empty_path

(* repo.ml *)
type error =
  | Db_error of string
  | Integrity_error of string
  | Not_found of Lid.t
  | Migration_error of string

(* protocol.ml *)
type protocol_error =
  | Invalid_lid of string * Lid.parse_error
  | Storage_error of string
  | Unknown_command of string
```

API layer converts to structured JSON:

```json
{
  "status": "error",
  "message": "Invalid LID 'bad::': empty path after colon"
}
```

## Results

### Good
- **AI understands error:** can try to fix it (for example, LID format)
- **Exhaustive handling:** compiler requires to handle all cases
- **Debugging:** logs show exact reason, not generic "error"

### Bad
- **Boilerplate:** need to define error types at each level
- **Mapping:** need to convert errors between layers

### Trade-offs
- `Storage_error of string` in Protocol — we lose structure of Repo error. This is by design: AI does not need SQLite details, enough to understand "storage problem"
- Exceptions are not used for control flow, only for programming errors (bugs in code)
