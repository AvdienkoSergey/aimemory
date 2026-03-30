# ADR-002: Pending Refs as Normal State

**Status:** Accepted
**Date:** 2026-03-30

## Context

AI describes code in any order. It may see a function call first, then the function itself later. Options:

1. **Error:** ref to missing entity — reject
2. **Ignore:** do not save ref until target appears
3. **Pending:** save ref, mark as unresolved

## Decision

Ref to missing entity is saved as `pending`. When target appears — ref becomes `resolved` automatically.

```ocaml
(* ref.ml *)
type resolution =
  | Resolved of resolved      (* both endpoints exist *)
  | Source_missing of pending
  | Target_missing of pending
  | Both_missing of pending
```

In database: `refs.resolved = 0|1`. On each emit we call `Repo.resolve_all`:

```sql
UPDATE refs SET resolved = 1
WHERE resolved = 0
  AND source_lid IN (SELECT lid FROM entities)
  AND target_lid IN (SELECT lid FROM entities)
```

## Results

### Good
- **Robust:** AI does not need to follow strict order
- **Incremental:** can add entities in parts
- **Diagnostics:** `status` shows what is not described yet

### Bad
- **Eventual consistency:** graph is incomplete until all entities are added
- **Orphan refs:** if target never appears, ref stays pending forever

### Trade-offs
- No automatic cleanup of orphan refs — this is by design (AI may add target later)
- `query_refs` returns only resolved — pending are not visible in normal queries
