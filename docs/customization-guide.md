# Customization Guide

aimemory has default kinds for frontend/Vue projects. If your project is different (backend, mobile, gamedev, ML) — you need to change the entity and relation vocabulary.

## See current vocabulary

```bash
aimemory kinds    # all entity kinds
aimemory rels     # all relation types
```

## How to apply changes

After any edit you **must** run:

```bash
dune build && dune install
```

`dune install` copies the binary to your opam switch (`~/.opam/<switch>/bin/aimemory`). Without this step the system uses the old binary. Your changes will not work.

Common mistake: running `opam install .` instead of `dune install`. Opam takes source from git, so uncommitted changes are ignored. Always use `dune install`.

## What to edit

You edit two files in `lib/domain/`. Enum lists in `tools.ml` are generated automatically — you do not need to touch them.

| What | File | Compiler helps? |
|---|---|---|
| Entity kinds | `lib/domain/lid.ml` | Yes (pattern match), except `all_kinds` |
| Relation types | `lib/domain/ref.ml` | Yes (pattern match), except `all_rels` |
| AI descriptions (optional) | `lib/api/tools.ml` | No (just strings) |

### Architecture decisions behind this design

- [ADR-001: LID format](adr/001-lid-format.md) — why `kind:path`, why a fixed set of kinds
- [ADR-004: Type contracts](adr/004-type-contracts.md) — raw vs processed entities, why the compiler catches mistakes
- [ADR-005: Layered architecture](adr/005-layered-architecture.md) — layer order: domain -> storage -> engine -> api

## Add a new kind

Example: a task tracker like Jira. AI agent builds a graph: epics contain stories, stories link to code components, bugs block releases, sprints group tasks.

We add `epic` — all edits in one file `lib/domain/lid.ml`, three places:

```ocaml
(* 1. Add variant to the type *)
and kind =
  | ...
  | Epic    (* <-- new *)

(* 2. Add string prefix — compiler will warn if you forget *)
let prefix_of_kind = function
  | ...
  | Epic -> "epic"

(* 3. Add to the list — compiler will NOT warn, do not forget *)
let all_kinds = [
  ...
  Epic;
]
```

`kind_of_prefix` (string -> kind) is computed automatically from `prefix_of_kind` + `all_kinds`. Enum in tool schemas is also generated from `all_kinds`.

Same way we add `Story`, `Bug`, `Sprint`, `Release`, `Board`. After all edits:

```bash
dune build && dune install
aimemory kinds              # check that epic, story, bug, ... are there
```

Now AI can fill the graph:

```bash
aimemory call emit '{
  "entities": [
    {"lid": "epic:PROJ-100",    "data": {"title": "Checkout redesign", "owner": "alice", "quarter": "Q2"}},
    {"lid": "story:PROJ-101",   "data": {"title": "New payment form", "points": 5, "status": "in_progress"}},
    {"lid": "story:PROJ-102",   "data": {"title": "Stripe integration", "points": 8, "status": "todo"}},
    {"lid": "bug:PROJ-150",     "data": {"title": "Double charge", "priority": "critical", "status": "open"}},
    {"lid": "sprint:2024-S12",  "data": {"goal": "MVP checkout", "start": "2024-03-18", "end": "2024-03-29"}},
    {"lid": "release:2.5.0",    "data": {"target_date": "2024-04-01", "status": "planned"}},
    {"lid": "comp:checkout/PaymentForm", "data": {"file": "src/checkout/PaymentForm.vue"}}
  ]
}'
```

And relations between them:

```bash
aimemory call emit '{
  "entities": [
    {"lid": "story:PROJ-101", "refs": [
      {"target": "epic:PROJ-100",              "rel": "belongs_to"},
      {"target": "comp:checkout/PaymentForm",  "rel": "references"},
      {"target": "sprint:2024-S12",            "rel": "belongs_to"}
    ]},
    {"lid": "bug:PROJ-150", "refs": [
      {"target": "story:PROJ-101",  "rel": "references"},
      {"target": "release:2.5.0",   "rel": "references"}
    ]},
    {"lid": "release:2.5.0", "refs": [
      {"target": "epic:PROJ-100",   "rel": "contains"}
    ]}
  ]
}'
```

Queries that AI can now make:

```bash
# What is in the "Checkout redesign" epic?
aimemory call query_refs '{"target": "epic:PROJ-100", "rel": "belongs_to"}'
# → story:PROJ-101, story:PROJ-102

# What bugs block release 2.5.0?
aimemory call query_refs '{"target": "release:2.5.0"}'
# → bug:PROJ-150

# What is in the current sprint?
aimemory call query_refs '{"target": "sprint:2024-S12", "rel": "belongs_to"}'
# → story:PROJ-101

# What code components does the story touch?
aimemory call query_refs '{"source": "story:PROJ-101", "rel": "references"}'
# → comp:checkout/PaymentForm
```

Optional: update description strings in `lib/api/tools.ml` (~line 330) where kind examples are listed for AI.

## Add a new relation type

Example: we add `trains_on` for ML pipelines.

All edits in one file — `lib/domain/ref.ml`, three places:

```ocaml
(* 1. Add variant to the type *)
type rel =
  | ...
  | Trains_on    (* <-- new *)

(* 2. Add string conversion — compiler will warn *)
let rel_to_string = function
  | ...
  | Trains_on -> "trains_on"

(* 3. Add to the list — compiler will NOT warn, do not forget *)
let all_rels = [...; Trains_on]
```

`rel_of_string` is computed automatically. Enum lists in tool schemas too.

```bash
dune build && dune install
aimemory rels               # check that trains_on is there
```

Optional: add a description for the new relation in `lib/api/tools.ml`.

## Remove kinds you do not need

If your project is a backend service, you do not need `Composable`, `View`, `Layout`, etc. Removing extra kinds helps AI focus.

1. Remove the variant from `type kind`, from `prefix_of_kind`, from `all_kinds` in `lid.ml`
2. The compiler will mark all other places that use the removed variant
3. If the database had data with old kinds — run `aimemory reset`

```bash
dune build && dune install
```

## Full example

See [Go REST API example](example-go-rest-api.md) — a complete walkthrough for a backend order service with handlers, services, repos, migrations, and workers.

## Checklist after customization

```bash
dune build              # compiler catches missing pattern matches
dune runtest            # tests check round-trip kind->string->kind
dune install            # install the updated binary
aimemory kinds          # visual check
aimemory rels           # visual check
```
