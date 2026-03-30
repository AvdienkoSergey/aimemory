(**
  Entity is like a card with information.
  Each card has different things written on it:
  - One card: "source: file, length: 2500"
  - Other card: "path: fn:auth:useAuth"

  We don't know what will be on the card.
  But we know: it will have pairs "key: value".
*)

(**
  Pairs "key: value" are collected in a list.
  Example: [("source", String "file"); ("length", Int 2500)]

  WHY pairs "key: value"?
  This is domain layer. We don't know where data comes from.
  Maybe JSON? Maybe YAML? Maybe something else?
  List of pairs is the simplest structure that works for all.
*)
type data = (string * value) list

(**
  What can be a value?
  This is the minimal set of types that can come from any source.

  WHY no Object type?
  This is our rule: nested objects are not allowed.
  If you have an object — make it a separate entity.
  Parser must reject nested objects with an error.

  WHY no raw array as entity?
  Entity must have named fields (key: value pairs).
  Raw array like ["a", "b"] has no field names.
  It is just data without structure — not an entity.
  Parser must reject raw arrays at top level.
*)
and value =
  | String of string
  | Int of int
  | Float of float
  | Bool of bool
  | List of value list
  | Null

(**
  Entity has two stages of life:

  1. RAW — data just arrived, we did nothing yet
     - Has lid (local id from source)
     - No real id yet

  2. PROCESSED — we saved it and added metadata
     - Has real id from database
     - Has timestamps (when created, when updated)
*)

(** Raw entity. Only lid is required. No id yet. *)
type raw = { lid : Lid.t; data : data }

(** Processed entity. Has both lid and id. Stored in database. *)
type processed = {
  id : int;
  lid : Lid.t;
  data : data;
  created : float; (* Unix timestamp *)
  updated : float;
}
