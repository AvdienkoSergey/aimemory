# ADR-004: Type Contracts (raw vs processed)

**Status:** Accepted
**Date:** 2026-03-30

## Context

Entity goes through pipeline: create => save to DB => read. Different data is available at different stages:

- Before save: no `id`, no `created/updated`
- After save: has `id`, has timestamps

Options for modeling:

1. **One type with optional fields:** `id: int option`
2. **Two types:** `raw` (before) and `processed` (after)
3. **Phantom types:** `Entity<'unsaved>`, `Entity<'saved>`

## Decision

Two separate types:

```ocaml
(* entity.ml *)
type raw = {
  lid : Lid.t;
  data : data
}

type processed = {
  id : int;           (* physical PK *)
  lid : Lid.t;
  data : data;
  created : float;    (* unix timestamp *)
  updated : float;
}
```

Contract in `Repo`:
- `upsert : raw -> processed` — cannot get `processed` without going to DB
- `find_by_lid : Lid.t -> processed option` — from DB always `processed`

## Results

### Good
- **Compile-time safety:** cannot use `raw.id` by mistake (it does not exist)
- **Explicit pipeline:** you can see where persistence happens
- **No nullability:** in `processed` all fields are always there

### Bad
- **Duplication:** `lid` and `data` in both types
- **Conversion:** need to map between types

### Trade-offs
- We do not use phantom types — they are harder to understand, and benefit is small
- `processed` is created only in `Repo` — module does not export constructor
