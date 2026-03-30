(** Database schema DDL. Single source of truth for table structure. Used by
    [Repo] during [open_db] migration.

    NOTE: No migration logic implemented. Current approach uses CREATE IF NOT
    EXISTS which handles additive changes only. This is acceptable for v0.1.0:
    - Data is ephemeral (AI can re-emit entities)
    - Schema is unstable, breaking changes expected
    - No production deployments yet

    When migrations become necessary (ALTER TABLE, production users with
    persistent data), implement version check in meta table + incremental DDL. *)

let version = 1

let create_entities =
  {|
  CREATE TABLE IF NOT EXISTS entities (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    lid     TEXT    UNIQUE NOT NULL,
    kind    TEXT    NOT NULL,
    path    TEXT    NOT NULL,
    data    TEXT    NOT NULL DEFAULT '{}',
    created REAL    NOT NULL DEFAULT (unixepoch('now','subsec')),
    updated REAL    NOT NULL DEFAULT (unixepoch('now','subsec'))
  );
|}

let create_refs =
  {|
  CREATE TABLE IF NOT EXISTS refs (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    source_lid TEXT NOT NULL,
    target_lid TEXT NOT NULL,
    rel_type   TEXT NOT NULL,
    resolved   INTEGER NOT NULL DEFAULT 0,
    UNIQUE(source_lid, target_lid, rel_type)
  );
|}

let create_meta =
  {|
  CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
  );
|}

let indices =
  [
    "CREATE INDEX IF NOT EXISTS idx_entities_kind ON entities(kind);";
    "CREATE INDEX IF NOT EXISTS idx_entities_path ON entities(path);";
    "CREATE INDEX IF NOT EXISTS idx_refs_source ON refs(source_lid);";
    "CREATE INDEX IF NOT EXISTS idx_refs_target ON refs(target_lid);";
    "CREATE INDEX IF NOT EXISTS idx_refs_unresolved ON refs(resolved) WHERE \
     resolved = 0;";
  ]

(** All DDL statements in order *)
let all_ddl = [ create_entities; create_refs; create_meta ] @ indices
