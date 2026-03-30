(* repo.ml — SQLite implementation of the Repo interface *)

type t = { db : Sqlite3.db; path : string [@warning "-69"] }

type error =
  | Db_error of string
  | Integrity_error of string
  | Not_found of Lid.t
  | Migration_error of string

type stats = {
  entity_count : int;
  ref_resolved_count : int;
  ref_pending_count : int;
}

let pp_error = function
  | Db_error s -> "Database error: " ^ s
  | Integrity_error s -> "Integrity error: " ^ s
  | Not_found lid -> "Not found: " ^ Lid.to_string lid
  | Migration_error s -> "Migration error: " ^ s

(* ---------- helpers ---------- *)

let rc_to_result rc db =
  match rc with
  | Sqlite3.Rc.OK | Sqlite3.Rc.DONE -> Ok ()
  | _ -> Error (Db_error (Sqlite3.errmsg db))

let exec_sql db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> Ok ()
  | rc ->
      Error
        (Db_error
           (Printf.sprintf "%s: %s" (Sqlite3.Rc.to_string rc)
              (Sqlite3.errmsg db)))

(** Collect rows from statement using a row parser. Functional style. *)
let collect_rows stmt parse_row =
  let rec loop acc =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        let acc' = match parse_row stmt with
          | Some v -> v :: acc
          | None -> acc
        in
        loop acc'
    | _ -> List.rev acc
  in
  loop []

(** Entity.value ↔ Yojson.Safe.t conversion *)
let rec value_to_json : Entity.value -> Yojson.Safe.t = function
  | Entity.String s -> `String s
  | Entity.Int i    -> `Int i
  | Entity.Float f  -> `Float f
  | Entity.Bool b   -> `Bool b
  | Entity.Null     -> `Null
  | Entity.List vs  -> `List (List.map value_to_json vs)

let rec json_to_value : Yojson.Safe.t -> Entity.value = function
  | `String s -> Entity.String s
  | `Int i    -> Entity.Int i
  | `Float f  -> Entity.Float f
  | `Bool b   -> Entity.Bool b
  | `Null     -> Entity.Null
  | `List vs  -> Entity.List (List.map json_to_value vs)
  | `Assoc _ as obj -> Entity.String (Yojson.Safe.to_string obj)
  | other     -> Entity.String (Yojson.Safe.to_string other)

(** Encode Entity.data => JSON string (for DB storage) *)
let encode_data (d : Entity.data) : string =
  `Assoc (List.map (fun (k, v) -> (k, value_to_json v)) d)
  |> Yojson.Safe.to_string

(** Decode JSON string => Entity.data (from DB storage) *)
let decode_data (s : string) : Entity.data =
  try
    match Yojson.Safe.from_string s with
    | `Assoc pairs -> List.map (fun (k, v) -> (k, json_to_value v)) pairs
    | _ -> []
  with _ -> []

(* ---------- lifecycle ---------- *)

let run_migrations db =
  let errs =
    List.filter_map
      (fun ddl ->
        match Sqlite3.exec db ddl with
        | Sqlite3.Rc.OK -> None
        | _ -> Some (Sqlite3.errmsg db))
      Schema.all_ddl
  in
  match errs with [] -> Ok () | e :: _ -> Error (Migration_error e)

let open_db path =
  Log.debug (fun m -> m "opening database: %s" path);
  try
    let db = Sqlite3.db_open path in
    ignore (Sqlite3.exec db "PRAGMA journal_mode=WAL;");
    ignore (Sqlite3.exec db "PRAGMA foreign_keys=ON;");
    match run_migrations db with
    | Ok () ->
        Log.info (fun m -> m "database opened: %s" path);
        Ok { db; path }
    | Error e ->
        Log.err (fun m -> m "migration failed: %s" (pp_error e));
        ignore (Sqlite3.db_close db);
        Error e
  with exn ->
    Log.err (fun m -> m "failed to open database: %s" (Printexc.to_string exn));
    Error (Db_error (Printexc.to_string exn))

let close t = ignore (Sqlite3.db_close t.db)

let with_db path f =
  match open_db path with
  | Error e -> Error e
  | Ok t ->
      let result =
        try f t
        with exn ->
          close t;
          raise exn
      in
      close t;
      result

(* ---------- transactions ---------- *)

let with_tx t f =
  match exec_sql t.db "BEGIN" with
  | Error e -> Error e
  | Ok () -> (
      match f t with
      | Ok v -> (
          match exec_sql t.db "COMMIT" with
          | Ok () -> Ok v
          | Error e ->
              ignore (exec_sql t.db "ROLLBACK");
              Error e)
      | Error e ->
          ignore (exec_sql t.db "ROLLBACK");
          Error e)

(* ---------- entity CRUD ---------- *)

let upsert t (raw : Entity.raw) =
  Log.debug (fun m -> m "upsert %s" (Lid.to_string raw.lid));
  let lid_s = Lid.to_string raw.lid in
  let kind_s = Lid.prefix_of_kind (Lid.kind raw.lid) in
  let path_s = Lid.path raw.lid in
  let data_s = encode_data raw.data in
  let sql =
    "INSERT INTO entities (lid, kind, path, data) VALUES (?, ?, ?, ?) ON \
     CONFLICT(lid) DO UPDATE SET data = excluded.data, updated = \
     unixepoch('now','subsec')"
  in
  let stmt = Sqlite3.prepare t.db sql in
  ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT lid_s));
  ignore (Sqlite3.bind stmt 2 (Sqlite3.Data.TEXT kind_s));
  ignore (Sqlite3.bind stmt 3 (Sqlite3.Data.TEXT path_s));
  ignore (Sqlite3.bind stmt 4 (Sqlite3.Data.TEXT data_s));
  match Sqlite3.step stmt with
  | Sqlite3.Rc.DONE -> (
      ignore (Sqlite3.finalize stmt);
      (* Fetch back the stored version *)
      let q =
        Sqlite3.prepare t.db
          "SELECT id, lid, data, created, updated FROM entities WHERE lid = ?"
      in
      ignore (Sqlite3.bind q 1 (Sqlite3.Data.TEXT lid_s));
      match Sqlite3.step q with
      | Sqlite3.Rc.ROW ->
          let id = Sqlite3.Data.to_int_exn (Sqlite3.column q 0) in
          let data =
            decode_data (Sqlite3.Data.to_string_exn (Sqlite3.column q 2))
          in
          let created = Sqlite3.Data.to_float_exn (Sqlite3.column q 3) in
          let updated = Sqlite3.Data.to_float_exn (Sqlite3.column q 4) in
          ignore (Sqlite3.finalize q);
          Ok Entity.{ id; lid = raw.lid; data; created; updated }
      | _ ->
          ignore (Sqlite3.finalize q);
          Error (Db_error "upsert succeeded but row not found"))
  | _ ->
      let msg = Sqlite3.errmsg t.db in
      ignore (Sqlite3.finalize stmt);
      Error (Db_error msg)

let upsert_many t raws =
  with_tx t (fun t ->
      let rec loop acc = function
        | [] -> Ok (List.rev acc)
        | raw :: rest -> (
            match upsert t raw with
            | Ok stored -> loop (stored :: acc) rest
            | Error e -> Error e)
      in
      loop [] raws)

let row_to_stored stmt =
  let id = Sqlite3.Data.to_int_exn (Sqlite3.column stmt 0) in
  let lid_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt 1) in
  let data_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt 2) in
  let created = Sqlite3.Data.to_float_exn (Sqlite3.column stmt 3) in
  let updated = Sqlite3.Data.to_float_exn (Sqlite3.column stmt 4) in
  match Lid.of_string lid_s with
  | Ok lid ->
      let data = decode_data data_s in
      Some Entity.{ id; lid; data; created; updated }
  | Error _ -> None

let find_by_lid t lid =
  let stmt =
    Sqlite3.prepare t.db
      "SELECT id, lid, data, created, updated FROM entities WHERE lid = ?"
  in
  ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT (Lid.to_string lid)));
  let result =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW -> Ok (row_to_stored stmt)
    | Sqlite3.Rc.DONE -> Ok None
    | _ -> Error (Db_error (Sqlite3.errmsg t.db))
  in
  ignore (Sqlite3.finalize stmt);
  result

let find_by_id t id =
  let stmt =
    Sqlite3.prepare t.db
      "SELECT id, lid, data, created, updated FROM entities WHERE id = ?"
  in
  ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.INT (Int64.of_int id)));
  let result =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW -> Ok (row_to_stored stmt)
    | Sqlite3.Rc.DONE -> Ok None
    | _ -> Error (Db_error (Sqlite3.errmsg t.db))
  in
  ignore (Sqlite3.finalize stmt);
  result

let query_entities t ?kind ?pattern ?limit ?offset () =
  let filters = List.filter_map Fun.id [
    Option.map (fun k -> (" AND kind = ?", Sqlite3.Data.TEXT (Lid.prefix_of_kind k))) kind;
    Option.map (fun p -> (" AND path LIKE ?", Sqlite3.Data.TEXT p)) pattern;
  ] in
  let where_clause = String.concat "" (List.map fst filters) in
  let bind_filters stmt start_idx =
    List.iteri (fun i (_, v) -> ignore (Sqlite3.bind stmt (start_idx + i) v)) filters
  in
  (* Count total *)
  let count_sql = "SELECT COUNT(*) FROM entities WHERE 1=1" ^ where_clause in
  let count_stmt = Sqlite3.prepare t.db count_sql in
  bind_filters count_stmt 1;
  let total = match Sqlite3.step count_stmt with
    | Sqlite3.Rc.ROW -> Sqlite3.Data.to_int_exn (Sqlite3.column count_stmt 0)
    | _ -> 0
  in
  ignore (Sqlite3.finalize count_stmt);
  (* Fetch page *)
  let base = "SELECT id, lid, data, created, updated FROM entities WHERE 1=1" in
  let pagination = match limit with
    | Some l ->
      let o = Option.value offset ~default:0 in
      Printf.sprintf " LIMIT %d OFFSET %d" l o
    | None -> ""
  in
  let sql = base ^ where_clause ^ " ORDER BY lid" ^ pagination in
  let stmt = Sqlite3.prepare t.db sql in
  bind_filters stmt 1;
  let results = collect_rows stmt row_to_stored in
  ignore (Sqlite3.finalize stmt);
  Ok (results, total)

let delete t lid =
  let lid_s = Lid.to_string lid in
  (* Delete refs first *)
  let del_refs =
    Sqlite3.prepare t.db
      "DELETE FROM refs WHERE source_lid = ? OR target_lid = ?"
  in
  ignore (Sqlite3.bind del_refs 1 (Sqlite3.Data.TEXT lid_s));
  ignore (Sqlite3.bind del_refs 2 (Sqlite3.Data.TEXT lid_s));
  ignore (Sqlite3.step del_refs);
  ignore (Sqlite3.finalize del_refs);
  (* Delete entity *)
  let del_ent = Sqlite3.prepare t.db "DELETE FROM entities WHERE lid = ?" in
  ignore (Sqlite3.bind del_ent 1 (Sqlite3.Data.TEXT lid_s));
  let rc = Sqlite3.step del_ent in
  ignore (Sqlite3.finalize del_ent);
  match rc with
  | Sqlite3.Rc.DONE -> Ok (Sqlite3.changes t.db > 0)
  | _ -> Error (Db_error (Sqlite3.errmsg t.db))

(* ---------- ref CRUD ---------- *)

let insert_ref t (p : Ref.pending) =
  let sql =
    "INSERT OR IGNORE INTO refs (source_lid, target_lid, rel_type, resolved) \
     VALUES (?, ?, ?, 0)"
  in
  let stmt = Sqlite3.prepare t.db sql in
  ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT (Lid.to_string p.source)));
  ignore (Sqlite3.bind stmt 2 (Sqlite3.Data.TEXT (Lid.to_string p.target)));
  ignore (Sqlite3.bind stmt 3 (Sqlite3.Data.TEXT (Ref.rel_to_string p.rel)));
  let rc = Sqlite3.step stmt in
  ignore (Sqlite3.finalize stmt);
  rc_to_result rc t.db

let insert_refs t refs =
  with_tx t (fun t ->
      let rec loop = function
        | [] -> Ok ()
        | r :: rest -> (
            match insert_ref t r with Ok () -> loop rest | Error e -> Error e)
      in
      loop refs)

(** Parse resolved ref row: source_lid, target_lid, rel_type, source_id, target_id *)
let row_to_resolved stmt =
  let src_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt 0) in
  let tgt_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt 1) in
  let rel_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt 2) in
  let src_id = Sqlite3.Data.to_int_exn (Sqlite3.column stmt 3) in
  let tgt_id = Sqlite3.Data.to_int_exn (Sqlite3.column stmt 4) in
  match Lid.of_string src_s, Lid.of_string tgt_s, Ref.rel_of_string rel_s with
  | Ok source, Ok target, Some rel ->
      Some Ref.{ source; target; rel; source_id = src_id; target_id = tgt_id }
  | _ -> None

(** Parse pending ref row: source_lid, target_lid, rel_type *)
let row_to_pending stmt =
  let src_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt 0) in
  let tgt_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt 1) in
  let rel_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt 2) in
  match Lid.of_string src_s, Lid.of_string tgt_s, Ref.rel_of_string rel_s with
  | Ok source, Ok target, Some rel -> Some Ref.{ source; target; rel }
  | _ -> None

let resolve_all t =
  let update_sql =
    "UPDATE refs SET resolved = 1 WHERE resolved = 0 AND source_lid IN (SELECT \
     lid FROM entities) AND target_lid IN (SELECT lid FROM entities)"
  in
  match exec_sql t.db update_sql with
  | Error e -> Error e
  | Ok () ->
      let resolved_sql =
        "SELECT r.source_lid, r.target_lid, r.rel_type, es.id, et.id FROM refs \
         r JOIN entities es ON es.lid = r.source_lid JOIN entities et ON \
         et.lid = r.target_lid WHERE r.resolved = 1"
      in
      let stmt_r = Sqlite3.prepare t.db resolved_sql in
      let resolved = collect_rows stmt_r row_to_resolved in
      ignore (Sqlite3.finalize stmt_r);
      let pending_sql =
        "SELECT source_lid, target_lid, rel_type FROM refs WHERE resolved = 0"
      in
      let stmt_p = Sqlite3.prepare t.db pending_sql in
      let pending = collect_rows stmt_p row_to_pending in
      ignore (Sqlite3.finalize stmt_p);
      Ok (resolved, pending)

let query_refs t ?source ?target ?rel ?limit ?offset () =
  let filters = List.filter_map Fun.id [
    Option.map (fun s -> (" AND r.source_lid = ?", Sqlite3.Data.TEXT (Lid.to_string s))) source;
    Option.map (fun t -> (" AND r.target_lid = ?", Sqlite3.Data.TEXT (Lid.to_string t))) target;
    Option.map (fun r -> (" AND r.rel_type = ?", Sqlite3.Data.TEXT (Ref.rel_to_string r))) rel;
  ] in
  let where_clause = String.concat "" (List.map fst filters) in
  let bind_filters stmt start_idx =
    List.iteri (fun i (_, v) -> ignore (Sqlite3.bind stmt (start_idx + i) v)) filters
  in
  (* Count total *)
  let count_sql =
    "SELECT COUNT(*) FROM refs r \
     JOIN entities es ON es.lid = r.source_lid \
     JOIN entities et ON et.lid = r.target_lid \
     WHERE r.resolved = 1" ^ where_clause
  in
  let count_stmt = Sqlite3.prepare t.db count_sql in
  bind_filters count_stmt 1;
  let total = match Sqlite3.step count_stmt with
    | Sqlite3.Rc.ROW -> Sqlite3.Data.to_int_exn (Sqlite3.column count_stmt 0)
    | _ -> 0
  in
  ignore (Sqlite3.finalize count_stmt);
  (* Fetch page *)
  let base =
    "SELECT r.source_lid, r.target_lid, r.rel_type, es.id, et.id FROM refs r \
     JOIN entities es ON es.lid = r.source_lid JOIN entities et ON et.lid = \
     r.target_lid WHERE r.resolved = 1"
  in
  let pagination = match limit with
    | Some l ->
      let o = Option.value offset ~default:0 in
      Printf.sprintf " LIMIT %d OFFSET %d" l o
    | None -> ""
  in
  let sql = base ^ where_clause ^ pagination in
  let stmt = Sqlite3.prepare t.db sql in
  bind_filters stmt 1;
  let results = collect_rows stmt row_to_resolved in
  ignore (Sqlite3.finalize stmt);
  Ok (results, total)

let pending_refs t =
  let sql =
    "SELECT source_lid, target_lid, rel_type FROM refs WHERE resolved = 0"
  in
  let stmt = Sqlite3.prepare t.db sql in
  let results = collect_rows stmt row_to_pending in
  ignore (Sqlite3.finalize stmt);
  Ok results

(* ---------- diagnostics ---------- *)

let count_sql db sql =
  let stmt = Sqlite3.prepare db sql in
  match Sqlite3.step stmt with
  | Sqlite3.Rc.ROW ->
      let n = Sqlite3.Data.to_int_exn (Sqlite3.column stmt 0) in
      ignore (Sqlite3.finalize stmt);
      Ok n
  | _ ->
      ignore (Sqlite3.finalize stmt);
      Error (Db_error (Sqlite3.errmsg db))

let stats t =
  match
    ( count_sql t.db "SELECT COUNT(*) FROM entities",
      count_sql t.db "SELECT COUNT(*) FROM refs WHERE resolved = 1",
      count_sql t.db "SELECT COUNT(*) FROM refs WHERE resolved = 0" )
  with
  | Ok ec, Ok rc, Ok pc ->
      Ok { entity_count = ec; ref_resolved_count = rc; ref_pending_count = pc }
  | Error e, _, _ | _, Error e, _ | _, _, Error e -> Error e

let all_lids t ?kind () =
  let row_to_lid stmt =
    let lid_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt 0) in
    Result.to_option (Lid.of_string lid_s)
  in
  let sql, bind = match kind with
    | Some k -> "SELECT lid FROM entities WHERE kind = ? ORDER BY lid",
                Some (Sqlite3.Data.TEXT (Lid.prefix_of_kind k))
    | None -> "SELECT lid FROM entities ORDER BY lid", None
  in
  let stmt = Sqlite3.prepare t.db sql in
  Option.iter (fun v -> ignore (Sqlite3.bind stmt 1 v)) bind;
  let results = collect_rows stmt row_to_lid in
  ignore (Sqlite3.finalize stmt);
  Ok results
