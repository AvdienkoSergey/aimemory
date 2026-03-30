# ADR-007: Query Pagination

**Status:** Accepted
**Date:** 2026-03-30

## Context

AI agent makes queries to context memory. Without limits `query_entities {}` can return thousands of records, which:
- Fills LLM context (typical limit is 100-200K tokens)
- Increases response latency
- Wastes tokens on data AI does not use

Options:

1. **No pagination** — AI filters via kind/pattern itself
2. **Offset pagination** — `limit` + `offset`, classic approach
3. **Cursor pagination** — `after: "lid:xxx"`, more stable when data changes

## Decision

**Offset pagination** with good defaults:

```json
{
  "kind": "fn",
  "pattern": "auth/*",
  "limit": 50,
  "offset": 0
}
```

Response includes metadata:
```json
{
  "entities": [...],
  "count": 50,
  "total": 1234,
  "has_more": true
}
```

### Defaults

| Parameter | Default | Max |
|-----------|---------|-----|
| limit | 100 | 1000 |
| offset | 0 | - |

### Why offset, not cursor

1. **Simplicity** — AI understands `offset: 100` better than `after: "fn:auth/login"`
2. **Random access** — can request any page
3. **Stateless** — no need to store cursor state
4. **Good enough for use case** — data changes rarely (AI creates it itself)

Cursor pagination is better for:
- Data that changes often (social networks)
- Infinite scroll in UI
- Strict consistency

For context memory this is overkill.

## Results

### Good
- **Controlled response size** — AI does not get more than needed
- **Transparency** — `total` shows how many exist, AI decides if it needs more
- **Backwards compatible** — without limit/offset works as before (with default limit)

### Bad
- **Offset inefficiency** — `OFFSET 10000` scans 10000 rows. For context memory this is not critical (rarely >10K entities)
- **Unstable on changes** — if entity is added between requests, offset shifts. For AI agent this is ok — it controls the data

### Trade-offs
- Default limit 100 — balance between "enough data" and "not fill context"
- Max limit 1000 — protection from accidental `limit: 999999`
- `total` is counted by separate COUNT query — small overhead, but important for AI
