# Customization Guide

> **Note:** This guide is a work in progress. Proper tooling for vocabulary
> customization (a config file, a generator, or an interactive wizard) is
> planned for a future release. Apologies for the rough edges.
>
> In the meantime: point your AI assistant at this file and the source files
> listed below. The strict OCaml type system and pattern-match exhaustiveness
> checks mean the compiler will catch most mistakes automatically — the AI can
> handle the mechanical edits. Your only job is the domain design: what entities
> exist in your system and how they relate to each other.

aimemory ships with a vocabulary tuned for a specific domain. The branch
[`jira-and-gitlab`](https://github.com/AvdienkoSergey/aimemory/tree/jira-and-gitlab)
replaces the original Vue/frontend kinds with entities for **Jira + GitLab**
collection. If your project needs a different domain, change the vocabulary.

## Current defaults (branch `jira-and-gitlab`)

```bash
aimemory kinds    # all entity kinds
aimemory rels     # all relation types
```

**Entity kinds:**

| Prefix | Kind | Example LID |
|---|---|---|
| `issue` | Jira issue/task | `issue:DBO-123` |
| `epic` | Jira epic | `epic:DBO-100` |
| `sprint` | Jira sprint | `sprint:42` |
| `board` | Jira board | `board:5` |
| `version` | Jira fix version | `version:1.2.3` |
| `jproject` | Jira project | `jproject:DBO` |
| `juser` | Jira user | `juser:ivan.petrov` |
| `mr` | GitLab merge request | `mr:backend/456` |
| `pipeline` | GitLab CI pipeline | `pipeline:789` |
| `job` | Pipeline job/step | `job:1234` |
| `commit` | Git commit | `commit:abc123def` |
| `branch` | Git branch | `branch:feature/login` |
| `deploy` | GitLab deployment | `deploy:prod/2024-01` |
| `release` | GitLab release | `release:v1.2.3` |
| `glproject` | GitLab project | `glproject:backend` |
| `gluser` | GitLab user | `gluser:ivan.petrov` |
| `milestone` | GitLab milestone | `milestone:Q1-2025` |

**Relation types:**

| Rel | Meaning |
|---|---|
| `linked_to` | Issue linked to MR via DevStatus or key in description |
| `belongs_to` | Issue in sprint; MR in pipeline |
| `contains` | Sprint contains issues; pipeline contains jobs |
| `triggered_by` | Pipeline triggered by MR push |
| `deployed_via` | Issue reached production via deployment |
| `reviewed_by` | MR reviewed by a GitLab user |
| `assigned_to` | Issue/MR assigned to a user |
| `references` | Generic fallback |

## How to apply changes

After any edit you **must** run:

```bash
dune build && dune install
```

`dune install` copies the binary to your opam switch (`~/.opam/<switch>/bin/aimemory`). Without this step the system uses the old binary.

Common mistake: running `opam install .` instead of `dune install`. Opam reads from git — uncommitted changes are ignored. Always use `dune install`.

## What to edit

| What | File | Compiler helps? |
|---|---|---|
| Entity kinds | `lib/domain/lid.ml` | Yes (pattern match), except `all_kinds` |
| Entity kinds (interface) | `lib/domain/lid.mli` | No — must mirror `lid.ml` manually |
| Relation types | `lib/domain/ref.ml` | Yes (pattern match), except `all_rels` |
| AI-facing descriptions | `lib/api/tools.ml` | No (plain strings) |
| Tests | `test/test_domain.ml`, `test/test_api.ml`, `test/test_engine.ml` | No |

### Why `lib/api/tools.ml` is not optional

`tools.ml` contains hardcoded string descriptions that the AI agent reads at runtime to know what kinds and rels exist. If you change `lid.ml` and `ref.ml` but skip `tools.ml`, the binary compiles fine — but the AI will still see the old vocabulary in its tool schemas and produce wrong LIDs.

There are **three places** to update in `tools.ml`:

1. **LID format description** (search for `"Logical ID in format"`) — lists every kind with examples, used in the `emit` tool schema.
2. **Kind filter description** (search for `"Filter by entity kind"`) — lists kinds for the `query_entities` tool.
3. **Rel filter description and enum** (search for `"Filter by rel"`) — lists rels for the `query_refs` tool. Also update the adjacent hardcoded list of rel strings in the same block.

### Why tests must be updated

The test suite uses concrete kind and rel values (e.g. `Lid.Fn`, `Ref.Calls`). After removing those variants the compiler will fail. Update all occurrences in:

- `test/test_domain.ml` — lid parsing, roundtrip, ref construction tests
- `test/test_api.ml` — JSON parsing and dispatch tests
- `test/test_engine.ml` — ingest and query engine tests
- `test/test_storage.ml` / `test/test_prop.ml` — if they reference specific kinds

Replace old kind/rel names with equivalents from the new vocabulary. The logic of each test stays the same — only the concrete values change.

### Architecture decisions behind this design

- [ADR-001: LID format](adr/001-lid-format.md) — why `kind:path`, why a fixed set of kinds
- [ADR-004: Type contracts](adr/004-type-contracts.md) — raw vs processed entities, why the compiler catches mistakes
- [ADR-005: Layered architecture](adr/005-layered-architecture.md) — layer order: domain -> storage -> engine -> api

## Add a new kind

Example: you want to track **Confluence pages** alongside Jira issues — so AI can link an issue to its spec page.

All edits in one file `lib/domain/lid.ml`, three places:

```ocaml
(* 1. Add variant to the type *)
and kind =
  | ...
  | ConfluencePage    (* <-- new *)

(* 2. Add string prefix — compiler will warn if you forget *)
let prefix_of_kind = function
  | ...
  | ConfluencePage -> "cfpage"

(* 3. Add to the list — compiler will NOT warn, do not forget *)
let all_kinds = [
  ...
  ConfluencePage;
]
```

`kind_of_prefix` (string → kind) is computed automatically from `prefix_of_kind` + `all_kinds`. The enum in tool schemas is also generated from `all_kinds`.

After edits:

```bash
dune build && dune install
aimemory kinds              # check that cfpage is there
```

Now AI can link issues to their specs:

```bash
aimemory call emit '{
  "entities": [
    {"lid": "issue:DBO-123",  "data": {"title": "Login redesign"}},
    {"lid": "cfpage:12345",   "data": {"title": "Login spec", "url": "https://confluence/pages/12345"}}
  ]
}'

aimemory call emit '{
  "entities": [
    {"lid": "issue:DBO-123", "refs": [
      {"target": "cfpage:12345", "rel": "references"}
    ]}
  ]
}'
```

Update `lib/api/tools.ml`: search for `"Logical ID in format"` and `"Filter by entity kind"` — add the new prefix to both description strings and their examples. Also update all tests in `test/test_domain.ml` and `test/test_api.ml` that construct LIDs with the old kinds.

## Add a new relation type

Example: you want `blocks` — a Jira issue blocks another issue.

All edits in one file `lib/domain/ref.ml`, three places:

```ocaml
(* 1. Add variant to the type *)
type rel =
  | ...
  | Blocks    (* <-- new *)

(* 2. Add string conversion — compiler will warn if you forget *)
let rel_to_string = function
  | ...
  | Blocks -> "blocks"

(* 3. Add to the list — compiler will NOT warn, do not forget *)
let all_rels = [...; Blocks]
```

`rel_of_string` is computed automatically. Enum lists in tool schemas too.

```bash
dune build && dune install
aimemory rels               # check that blocks is there
```

Usage:

```bash
aimemory call emit '{
  "entities": [
    {"lid": "issue:DBO-150", "refs": [
      {"target": "issue:DBO-123", "rel": "blocks"}
    ]}
  ]
}'

# What is blocked by DBO-150?
aimemory call query_refs '{"source": "issue:DBO-150", "rel": "blocks"}'
```

Update `lib/api/tools.ml`: add the new rel string to the hardcoded enum list (search for `"linked_to"` to find it) and update the `"Filter by rel"` description string. Also update tests in `test/test_domain.ml` and `test/test_engine.ml` that use specific rel values.

## Remove kinds you do not need

If you only collect Jira data and do not need GitLab entities, remove the GitLab kinds to help AI focus.

1. Remove the variants (`MergeRequest`, `Pipeline`, `Job`, `Commit`, `Branch`, `Deployment`, `Release`, `GlProject`, `GlUser`, `Milestone`) from `type kind`, `prefix_of_kind`, and `all_kinds` in `lib/domain/lid.ml`
2. Also remove `lid.mli` declarations for those variants
3. The compiler marks every other place that referenced the removed variants
4. If the database had data with old kinds — run `aimemory reset`

```bash
dune build && dune install
```

## Example: querying a Jira+GitLab graph

```bash
# Store a sprint with issues
aimemory call emit '{
  "entities": [
    {"lid": "sprint:42",      "data": {"name": "Sprint 42", "start": "2024-03-18", "end": "2024-03-29"}},
    {"lid": "issue:DBO-101",  "data": {"title": "Add login", "status": "in_progress", "points": 5}},
    {"lid": "issue:DBO-102",  "data": {"title": "Fix logout", "status": "todo", "points": 2}},
    {"lid": "mr:backend/78",  "data": {"title": "login: implement JWT", "state": "opened"}},
    {"lid": "pipeline:789",   "data": {"status": "running", "ref": "feature/login"}}
  ]
}'

aimemory call emit '{
  "entities": [
    {"lid": "issue:DBO-101", "refs": [
      {"target": "sprint:42",       "rel": "belongs_to"},
      {"target": "mr:backend/78",   "rel": "linked_to"}
    ]},
    {"lid": "mr:backend/78", "refs": [
      {"target": "pipeline:789",    "rel": "triggered_by"}
    ]}
  ]
}'

# What issues are in sprint 42?
aimemory call query_refs '{"target": "sprint:42", "rel": "belongs_to"}'
# → issue:DBO-101, issue:DBO-102

# What MR is linked to DBO-101?
aimemory call query_refs '{"source": "issue:DBO-101", "rel": "linked_to"}'
# → mr:backend/78

# What pipeline did that MR trigger?
aimemory call query_refs '{"source": "mr:backend/78", "rel": "triggered_by"}'
# → pipeline:789
```

## Checklist after customization

```bash
dune build              # compiler catches missing pattern matches in lid.ml / ref.ml
dune runtest            # tests check round-trip kind->string->kind and rel->string->rel
dune install            # install the updated binary
aimemory kinds          # visual check — new kinds must appear here
aimemory rels           # visual check — new rels must appear here
```

**Common pitfall:** `dune build` passes but `dune runtest` fails — this usually means
`tools.ml` or the tests still reference old kind/rel names. Fix those and re-run.
