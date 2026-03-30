(** Resolver — turns pending refs into resolved refs.

    Operates on top of [Repo]. Provides batch resolution,
    diagnostics, and pattern-based entity lookup.

    Type contracts:
    - [resolve] takes [Ref.pending list] → partitions into
      [Ref.resolved list * Ref.pending list]
    - Resolution is idempotent — calling twice yields same result
    - All IO goes through [Repo.t], no direct SQLite access *)

(** Result of a resolution pass *)
type resolution_result = {
  resolved : Ref.resolved list;   (** successfully linked *)
  pending  : Ref.pending list;    (** still waiting for target/source *)
  errors   : resolution_error list;
}

and resolution_error = {
  ref_    : Ref.pending;
  reason : string;
}

(** Empty result — identity for merging *)
let empty_result = {
  resolved = [];
  pending = [];
  errors = [];
}

(** Merge two resolution results *)
let merge a b = {
  resolved = a.resolved @ b.resolved;
  pending = a.pending @ b.pending;
  errors = a.errors @ b.errors;
}

(** {1 Core resolution} *)

(** Resolve all pending refs in the database.
    Delegates to [Repo.resolve_all] which marks refs as resolved
    when both source and target entities exist. *)
let resolve_all (db : Repo.t) : (resolution_result, Repo.error) result =
  match Repo.resolve_all db with
  | Ok (resolved, pending) ->
    Ok { resolved; pending; errors = [] }
  | Error e -> Error e

(** Resolve a specific list of pending refs against current DB state.
    Unlike [resolve_all], this works on an explicit list — useful
    right after inserting new refs from a single AI response. *)
let resolve_pending (db : Repo.t) (refs : Ref.pending list)
    : (resolution_result, Repo.error) result =
  (* Build a lookup cache: LID → physical ID *)
  let cache : (string, int) Hashtbl.t = Hashtbl.create 64 in
  let lookup lid =
    let key = Lid.to_string lid in
    match Hashtbl.find_opt cache key with
    | Some id -> Ok (Some id)
    | None ->
      match Repo.find_by_lid db lid with
      | Ok (Some stored) ->
        Hashtbl.replace cache key stored.Entity.id;
        Ok (Some stored.Entity.id)
      | Ok None -> Ok None
      | Error e -> Error e
  in
  let rec loop resolved pending = function
    | [] -> Ok { resolved = List.rev resolved;
                 pending = List.rev pending;
                 errors = [] }
    | (r : Ref.pending) :: rest ->
      match lookup r.source, lookup r.target with
      | Ok (Some src_id), Ok (Some tgt_id) ->
        let res = Ref.{
          source = r.source; target = r.target;
          rel = r.rel;
          source_id = src_id; target_id = tgt_id;
        } in
        loop (res :: resolved) pending rest
      | Ok _, Ok _ ->
        loop resolved (r :: pending) rest
      | Error e, _ | _, Error e -> Error e
  in
  loop [] [] refs


(** {1 Pattern matching} *)

(** Simple glob matcher: supports [*] as wildcard.
    Used for entity queries like ["auth/*"]. *)
let glob_matches ~pattern s =
  (* Convert glob to a simple check *)
  if String.equal pattern "*" then true
  else if String.length pattern = 0 then String.length s = 0
  else
    let pat_len = String.length pattern in
    (* Check for trailing * *)
    if pattern.[pat_len - 1] = '*' then
      let prefix = String.sub pattern 0 (pat_len - 1) in
      let plen = String.length prefix in
      String.length s >= plen && String.sub s 0 plen = prefix
    (* Check for leading * *)
    else if pattern.[0] = '*' then
      let suffix = String.sub pattern 1 (pat_len - 1) in
      let slen = String.length suffix in
      let s_len = String.length s in
      s_len >= slen && String.sub s (s_len - slen) slen = suffix
    (* Exact match *)
    else String.equal pattern s

(** Convert a glob pattern to SQL LIKE pattern.
    ["auth/*"] → ["auth/%"] *)
let glob_to_like pattern =
  let buf = Buffer.create (String.length pattern) in
  String.iter (fun c ->
    match c with
    | '*' -> Buffer.add_char buf '%'
    | '?' -> Buffer.add_char buf '_'
    | '%' -> Buffer.add_string buf "\\%"
    | '_' -> Buffer.add_string buf "\\_"
    | c -> Buffer.add_char buf c
  ) pattern;
  Buffer.contents buf

(** Query entities using protocol's [entity_query] with glob support. *)
let query_entities (db : Repo.t) (q : Protocol.entity_query)
    : (Entity.processed list, Repo.error) result =
  let pattern = match q.pattern with
    | Some p -> Some (glob_to_like p)
    | None -> None
  in
  Repo.query_entities db ?kind:q.kind ?pattern ()

(** Query refs using protocol's [ref_query]. *)
let query_refs (db : Repo.t) (q : Protocol.ref_query)
    : (Ref.resolved list, Repo.error) result =
  Repo.query_refs db ?source:q.source ?target:q.target ?rel:q.rel_type ()


(** {1 Diagnostics} *)

(** Analyze pending refs — group by missing LID to help
    identify what the next AI prompt should produce. *)
type missing_analysis = {
  missing_lids : (Lid.t * int) list;  (** LID × number of refs waiting for it *)
  total_pending : int;
}

let analyze_pending (db : Repo.t) : (missing_analysis, Repo.error) result =
  match Repo.pending_refs db with
  | Error e -> Error e
  | Ok pending ->
    let counts : (string, Lid.t * int) Hashtbl.t = Hashtbl.create 32 in
    let check_lid lid =
      let key = Lid.to_string lid in
      match Repo.find_by_lid db lid with
      | Ok None ->
        let (_, n) = try Hashtbl.find counts key
                     with Not_found -> (lid, 0) in
        Hashtbl.replace counts key (lid, n + 1)
      | _ -> ()
    in
    List.iter (fun (r : Ref.pending) ->
      check_lid r.source;
      check_lid r.target
    ) pending;
    let missing_lids =
      Hashtbl.fold (fun _ (lid, n) acc -> (lid, n) :: acc) counts []
      |> List.sort (fun (_, a) (_, b) -> compare b a)  (* most-waited first *)
    in
    Ok { missing_lids; total_pending = List.length pending }

(** Human-readable summary of what's missing. *)
let pp_missing_analysis (a : missing_analysis) : string =
  if a.total_pending = 0 then
    "All references resolved."
  else
    let lines = List.map (fun (lid, n) ->
      Printf.sprintf "  %s (blocking %d ref%s)"
        (Lid.to_string lid) n (if n > 1 then "s" else "")
    ) a.missing_lids in
    Printf.sprintf "%d pending ref(s), missing entities:\n%s"
      a.total_pending (String.concat "\n" lines)