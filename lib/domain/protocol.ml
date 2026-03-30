type command =
  | Emit of emit_payload          (** save entities with refs *)
  | Query_entities of entity_query  (** find entities by kind/pattern *)
  | Query_refs of ref_query        (** find refs by source/target/rel *)

and emit_payload = { entities : entity_input list }

and entity_input = {
  lid : Lid.t;
  data : Entity.data;
  refs : ref_input list;
}

and ref_input = {
  target : Lid.t;
  rel : Ref.rel;
}

and entity_query = {
  kind : Lid.kind option;     (** filter by kind: Some Fn, Some Comp *)
  pattern : string option;    (** glob on path: "auth/*", "*Button*" *)
  limit : int option;         (** max results, default 100, max 1000 *)
  offset : int option;        (** skip first N results *)
}

and ref_query = {
  source : Lid.t option;      (** who links? — outgoing refs *)
  target : Lid.t option;      (** who is linked to? — incoming refs *)
  rel_type : Ref.rel option;  (** filter by rel: Some Calls *)
  limit : int option;
  offset : int option;
}

type page_info = {
  total : int;      (** total matching records *)
  has_more : bool;  (** are there more pages? *)
}

type response =
  | Emit_result of emit_result
  | Entities of entities_result
  | Refs of refs_result
  | Error of protocol_error

and entities_result = {
  items : Entity.processed list;
  page : page_info;
}

and refs_result = {
  items : Ref.resolved list;
  page : page_info;
}

(* WHY split resolved/pending? AI can describe code in any order. *)
and emit_result = {
  upserted : Lid.t list;
  refs_resolved : Ref.resolved list;
  refs_pending : Ref.pending list;
}

(* WHY typed errors? AI can understand what to fix. *)
and protocol_error =
  | Invalid_lid of string * Lid.parse_error
  | Storage_error of string
  | Unknown_command of string

let query_all_entities : entity_query =
  { kind = None; pattern = None; limit = None; offset = None }
let query_all_refs : ref_query =
  { source = None; target = None; rel_type = None; limit = None; offset = None }
