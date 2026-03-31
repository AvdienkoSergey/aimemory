(** Resolver — turns pending refs into resolved refs.

    Operates on top of [Repo]. Provides batch resolution, diagnostics, and
    pattern-based entity lookup.

    Type contracts:
    - [resolve] takes [Ref.pending list] => partitions into
      [Ref.resolved list * Ref.pending list]
    - Resolution is idempotent — calling twice yields same result
    - All IO goes through [Repo.t], no direct SQLite access *)

type resolution_result = {
  resolved : Ref.resolved list;  (** successfully linked *)
  pending : Ref.pending list;  (** still waiting for target/source *)
  errors : resolution_error list;
}
(** Result of a resolution pass *)

and resolution_error = { ref_ : Ref.pending; reason : string }

(** Empty result — identity for merging *)
let empty_result = { resolved = []; pending = []; errors = [] }

(** Merge two resolution results *)
let merge a b =
  {
    resolved = a.resolved @ b.resolved;
    pending = a.pending @ b.pending;
    errors = a.errors @ b.errors;
  }

(** {1 Core resolution} *)

(** Resolve all pending refs in the database. Delegates to [Repo.resolve_all]
    which marks refs as resolved when both source and target entities exist. *)
let resolve_all (db : Repo.t) : (resolution_result, Repo.error) result =
  match Repo.resolve_all db with
  | Ok (resolved, pending) -> Ok { resolved; pending; errors = [] }
  | Error e -> Error e

(** Resolve a specific list of pending refs against current DB state. Unlike
    [resolve_all], this works on an explicit list — useful right after inserting
    new refs from a single AI response. *)
let resolve_pending (db : Repo.t) (refs : Ref.pending list) :
    (resolution_result, Repo.error) result =
  (* Build a lookup cache: LID => physical ID *)
  let cache : (string, int) Hashtbl.t = Hashtbl.create 64 in
  let lookup lid =
    let key = Lid.to_string lid in
    match Hashtbl.find_opt cache key with
    | Some id -> Ok (Some id)
    | None -> (
        match Repo.find_by_lid db lid with
        | Ok (Some stored) ->
            Hashtbl.replace cache key stored.Entity.id;
            Ok (Some stored.Entity.id)
        | Ok None -> Ok None
        | Error e -> Error e)
  in
  let rec loop resolved pending = function
    | [] ->
        Ok
          {
            resolved = List.rev resolved;
            pending = List.rev pending;
            errors = [];
          }
    | (r : Ref.pending) :: rest -> (
        match (lookup r.source, lookup r.target) with
        | Ok (Some src_id), Ok (Some tgt_id) ->
            let res =
              Ref.
                {
                  source = r.source;
                  target = r.target;
                  rel = r.rel;
                  source_id = src_id;
                  target_id = tgt_id;
                }
            in
            loop (res :: resolved) pending rest
        | Ok _, Ok _ -> loop resolved (r :: pending) rest
        | Error e, _ | _, Error e -> Error e)
  in
  loop [] [] refs

(** Convert a glob pattern to SQL LIKE pattern. ["auth/*"] => ["auth/%"] *)
let glob_to_like pattern =
  let buf = Buffer.create (String.length pattern) in
  String.iter
    (fun c ->
      match c with
      | '*' -> Buffer.add_char buf '%'
      | '?' -> Buffer.add_char buf '_'
      | '%' -> Buffer.add_string buf "\\%"
      | '_' -> Buffer.add_string buf "\\_"
      | c -> Buffer.add_char buf c)
    pattern;
  Buffer.contents buf

let default_limit = 100
let max_limit = 1000

let effective_limit limit =
  match limit with
  | None -> Some default_limit
  | Some l -> Some (min l max_limit)

(** Query entities using protocol's [entity_query] with glob support. *)
let query_entities (db : Repo.t) (q : Protocol.entity_query) :
    (Protocol.entities_result, Repo.error) result =
  let pattern =
    match q.pattern with Some p -> Some (glob_to_like p) | None -> None
  in
  let limit = effective_limit q.limit in
  match
    Repo.query_entities db ?kind:q.kind ?pattern ?limit ?offset:q.offset ()
  with
  | Ok (items, total) ->
      let count = List.length items in
      let offset = Option.value q.offset ~default:0 in
      let has_more = offset + count < total in
      Ok Protocol.{ items; page = { total; has_more } }
  | Error e -> Error e

(** Query refs using protocol's [ref_query]. *)
let query_refs (db : Repo.t) (q : Protocol.ref_query) :
    (Protocol.refs_result, Repo.error) result =
  let limit = effective_limit q.limit in
  match
    Repo.query_refs db ?source:q.source ?target:q.target ?rel:q.rel_type ?limit
      ?offset:q.offset ()
  with
  | Ok (items, total) ->
      let count = List.length items in
      let offset = Option.value q.offset ~default:0 in
      let has_more = offset + count < total in
      Ok Protocol.{ items; page = { total; has_more } }
  | Error e -> Error e

(** {1 Diagnostics} *)

type missing_analysis = {
  missing_lids : (Lid.t * int) list;  (** LID × number of refs waiting for it *)
  total_pending : int;
}
(** Analyze pending refs — group by missing LID to help identify what the next
    AI prompt should produce. *)

let analyze_pending (db : Repo.t) : (missing_analysis, Repo.error) result =
  match Repo.pending_refs db with
  | Error e -> Error e
  | Ok pending ->
      let counts : (string, Lid.t * int) Hashtbl.t = Hashtbl.create 32 in
      let check_lid lid =
        let key = Lid.to_string lid in
        match Repo.find_by_lid db lid with
        | Ok None ->
            let _, n =
              try Hashtbl.find counts key with Not_found -> (lid, 0)
            in
            Hashtbl.replace counts key (lid, n + 1)
        | _ -> ()
      in
      List.iter
        (fun (r : Ref.pending) ->
          check_lid r.source;
          check_lid r.target)
        pending;
      let missing_lids =
        Hashtbl.fold (fun _ (lid, n) acc -> (lid, n) :: acc) counts []
        |> List.sort (fun (_, a) (_, b) -> compare b a)
        (* most-waited first *)
      in
      Ok { missing_lids; total_pending = List.length pending }

(** Human-readable summary of what's missing. *)
let pp_missing_analysis (a : missing_analysis) : string =
  if a.total_pending = 0 then
    "All references resolved."
  else
    let lines =
      List.map
        (fun (lid, n) ->
          Printf.sprintf "  %s (blocking %d ref%s)" (Lid.to_string lid) n
            (if n > 1 then
               "s"
             else
               ""))
        a.missing_lids
    in
    Printf.sprintf "%d pending ref(s), missing entities:\n%s" a.total_pending
      (String.concat "\n" lines)
