(** Repository — persistence layer for context-memory.

    All operations are typed through domain types. SQLite is an implementation
    detail hidden behind [t].

    Type-driven contracts:
    - [upsert] accepts [Entity.raw] (no PK) → returns [Entity.processed] (has PK)
    - [insert_ref] accepts [Ref.pending] (unverified) → stores it
    - [resolve_all] returns [Ref.resolved] for successful, [Ref.pending] for
      waiting
    - You cannot construct [Entity.processed] without going through this module *)

(** {1 Handle & lifecycle} *)

type t
(** Abstract database handle. Opaque — cannot be inspected or constructed
    outside this module. *)

(** Storage-level errors. Domain code never sees SQLite exceptions. *)
type error =
  | Db_error of string  (** SQLite error with message *)
  | Integrity_error of string  (** constraint violation *)
  | Not_found of Lid.t  (** entity with this LID not in DB *)
  | Migration_error of string  (** schema setup failed *)

val pp_error : error -> string

val open_db : string -> (t, error) result
(** Open a database at the given path. Creates file if absent. Runs migrations
    to ensure schema is current. Use [":memory:"] for in-memory database
    (testing). *)

val close : t -> unit
(** Close the database handle. *)

val with_db : string -> (t -> ('a, error) result) -> ('a, error) result
(** [with_db path f] — bracket pattern. Opens DB, runs [f], closes. Returns
    [Error] if open fails; otherwise returns [f]'s result. *)

(** {1 Transactions} *)

val with_tx : t -> (t -> ('a, error) result) -> ('a, error) result
(** [with_tx db f] — run [f] inside a transaction. Commits on [Ok], rolls back
    on [Error] or exception. Transactions nest via SAVEPOINTs. *)

(** {1 Entity CRUD} *)

val upsert : t -> Entity.raw -> (Entity.processed, error) result
(** Insert or update an entity by LID.
    - If LID is new: INSERT, assign auto-increment PK.
    - If LID exists: UPDATE data, bump [updated] timestamp. Returns the
      [Entity.processed] with physical ID — proof of persistence. *)

val upsert_many : t -> Entity.raw list -> (Entity.processed list, error) result
(** Batch upsert inside an implicit transaction. Returns stored entities in the
    same order as input. *)

val find_by_lid : t -> Lid.t -> (Entity.processed option, error) result
(** Find entity by logical ID. *)

val find_by_id : t -> int -> (Entity.processed option, error) result
(** Find entity by physical PK. *)

val query_entities :
  t ->
  ?kind:Lid.kind ->
  ?pattern:string ->
  unit ->
  (Entity.processed list, error) result
(** Query entities with optional filters. [?kind] — filter by entity kind
    (prefix of LID). [?pattern] — SQL LIKE pattern on the path portion, e.g.
    ["auth/%"]. *)

val delete : t -> Lid.t -> (bool, error) result
(** Delete entity by LID. Also deletes all refs where this LID is source or
    target. Returns [true] if entity existed. *)

(** {1 Reference CRUD} *)

val insert_ref : t -> Ref.pending -> (unit, error) result
(** Insert a pending reference. Does NOT check if source/target exist — that's
    the resolver's job. Idempotent: (source, target, rel) is a unique
    constraint; duplicate inserts are silently ignored. *)

val insert_refs : t -> Ref.pending list -> (unit, error) result
(** Batch insert pending refs. *)

val resolve_all : t -> (Ref.resolved list * Ref.pending list, error) result
(** Resolve all currently-pending refs whose both endpoints now exist. Returns a
    pair: (newly resolved, still pending). *)

val query_refs :
  t ->
  ?source:Lid.t ->
  ?target:Lid.t ->
  ?rel:Ref.rel ->
  unit ->
  (Ref.resolved list, error) result
(** Query refs with optional filters. Only returns resolved refs (both endpoints
    exist). *)

val pending_refs : t -> (Ref.pending list, error) result
(** Get all pending (unresolved) refs. Useful for diagnostics. *)

(** {1 Diagnostics} *)

type stats = {
  entity_count : int;
  ref_resolved_count : int;
  ref_pending_count : int;
}
(** Summary statistics *)

val stats : t -> (stats, error) result

val all_lids : t -> ?kind:Lid.kind -> unit -> (Lid.t list, error) result
(** List all known LIDs, optionally filtered by kind. *)
