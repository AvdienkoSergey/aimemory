# ADR-005: Layered Architecture

**Status:** Accepted
**Date:** 2026-03-30

## Context

System has several jobs:
- Define data types (Lid, Entity, Ref)
- Save to SQLite
- Business logic (emit pipeline, resolution)
- JSON API for AI

Options for organization:

1. **Monolith:** everything in one module
2. **Feature-based:** by features (emit/, query/)
3. **Layered:** by abstraction levels

## Decision

Five layers with clear dependencies:

```
API (Tools)           <= JSON boundary
    |
Engine (Ingest, Resolver)  <= business logic
    |
Storage (Repo, Schema)     <= persistence
    |
Domain (Lid, Entity, Ref, Protocol)  <= pure types
    |
Support (Log)              <= infrastructure
```

**Dependency rule:** arrows go only down. Domain does not know about Storage. Storage does not know about Engine.

Implementation via dune libraries:
```
lib/domain/dune   => (libraries sexplib0)
lib/storage/dune  => (libraries domain support sqlite3 yojson)
lib/engine/dune   => (libraries domain support storage)
lib/api/dune      => (libraries domain support storage engine yojson)
```

## Results

### Good
- **Testability:** Domain can be tested without DB
- **Replaceability:** can replace SQLite with Postgres, changing only Storage
- **Clarity:** new developer knows where to look

### Bad
- **Indirection:** more files, more imports
- **Rigidity:** harder to add "convenient" shortcuts across layers

### Trade-offs
- Support (Log) is a separate layer, though used everywhere. This is by design: logging is cross-cutting concern, but should not pull dependencies
- Protocol is in Domain, though it describes API. Reason: Protocol is pure types without IO, API-specific JSON parsing is in Tools
