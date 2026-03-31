# Requirements

## Functional Requirements

### FR-1: Entity Management

- **FR-1.1** The system shall store entities identified by a Logical ID (LID) in `kind:path` format.
- **FR-1.2** The system shall support upsert semantics — creating new entities or updating existing ones.
- **FR-1.3** The system shall support querying entities by kind and/or path pattern.
- **FR-1.4** The system shall support pagination for entity queries (offset, limit).
- **FR-1.5** The system shall store arbitrary key-value metadata (`data`) for each entity.
- **FR-1.6** The system shall track creation and update timestamps for entities.

### FR-2: Relation Management

- **FR-2.1** The system shall store directed relations (refs) between entities.
- **FR-2.2** The system shall support a fixed set of relation types: `belongs_to`, `calls`, `depends_on`, `contains`, `implements`, `renders`, `references`.
- **FR-2.3** The system shall support querying relations by source, target, or relation type.
- **FR-2.4** The system shall support pagination for relation queries.

### FR-3: Pending Reference Resolution

- **FR-3.1** When a relation target does not yet exist, the system shall store the relation as `pending`.
- **FR-3.2** When the target entity is created, the system shall automatically resolve pending relations to `resolved`.
- **FR-3.3** The system shall report the count of pending and resolved relations in status diagnostics.

### FR-4: CLI Interface

- **FR-4.1** The system shall provide a CLI with subcommands: `call`, `status`, `reset`, `mcp`, `kinds`, `rels`, `schemas`.
- **FR-4.2** The `call` subcommand shall accept a tool name and JSON arguments.
- **FR-4.3** The system shall support `--verbose` and `--quiet` flags for log control.

### FR-5: MCP Server

- **FR-5.1** The system shall provide an MCP server over stdio using JSON-RPC 2.0 protocol.
- **FR-5.2** The MCP server shall expose tools: `emit`, `query_entities`, `query_refs`, `status`.
- **FR-5.3** The MCP server shall respond with structured JSON results.

### FR-6: Configurable Vocabulary

- **FR-6.1** The system shall define entity kinds as an algebraic data type (ADT) for compile-time safety.
- **FR-6.2** The system shall define relation types as an ADT for compile-time safety.
- **FR-6.3** The vocabulary shall be customizable by modifying the source types and recompiling.

## Non-Functional Requirements

### NFR-1: Performance

- **NFR-1.1** Entity upsert shall complete in under 10ms for a single entity on commodity hardware.
- **NFR-1.2** Queries shall support up to 1000 results per page.
- **NFR-1.3** SQLite busy timeout shall prevent locking errors under concurrent access.

### NFR-2: Reliability

- **NFR-2.1** All database writes shall use transactions for atomicity.
- **NFR-2.2** Errors shall be typed at each layer (domain, storage, engine, API) for precise handling.
- **NFR-2.3** The system shall not crash on malformed input — errors are returned as JSON.

### NFR-3: Portability

- **NFR-3.1** The system shall build and run on Linux (x86_64), macOS (arm64), and Windows (x86_64).
- **NFR-3.2** The system shall compile with OCaml >= 5.1.
- **NFR-3.3** The only runtime dependency shall be SQLite (bundled via the `sqlite3` opam package).

### NFR-4: Maintainability

- **NFR-4.1** The architecture shall follow a layered design: Domain, Storage, Engine, API, Support.
- **NFR-4.2** Each layer shall have its own dune library with explicit dependency declarations.
- **NFR-4.3** Exhaustive pattern matching shall be used throughout — the compiler catches missing cases.

## Constraints

- **C-1** Storage is SQLite only — no external database server required.
- **C-2** MCP transport is stdio only — no HTTP, no WebSocket.
- **C-3** Entity and relation types are compile-time fixed — runtime extensibility is explicitly not supported (by design, see [ADR-001](adr/001-lid-format.md)).

## Assumptions

- **A-1** The AI agent interacting with the system can produce valid JSON.
- **A-2** Entities are described incrementally — the agent may describe targets before sources.
- **A-3** The database file is local to the project directory.
