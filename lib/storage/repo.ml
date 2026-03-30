(* repo.ml — SQLite implementation of the Repo interface *)

type t = { db : Sqlite3.db }

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

(** Encode Entity.data as a simple JSON string (manual — no dep on yojson) *)
let rec encode_value = function
  | Entity.String s ->
      let escaped = String.concat "\\\"" (String.split_on_char '"' s) in
      "\"" ^ escaped ^ "\""
  | Entity.Int i -> string_of_int i
  | Entity.Float f -> string_of_float f
  | Entity.Bool b -> if b then "true" else "false"
  | Entity.Null -> "null"
  | Entity.List vs -> "[" ^ String.concat "," (List.map encode_value vs) ^ "]"

let encode_data (d : Entity.data) : string =
  let pairs = List.map (fun (k, v) -> "\"" ^ k ^ "\":" ^ encode_value v) d in
  "{" ^ String.concat "," pairs ^ "}"

(** Minimal JSON string/number/bool/null parser for Entity.data. Handles the
    subset we produce in [encode_data]. *)
let decode_data (s : string) : Entity.data =
  (* Minimal parser — sufficient for our own output *)
  let len = String.length s in
  let pos = ref 0 in
  let peek () = if !pos < len then Some s.[!pos] else None in
  let advance () = incr pos in
  let rec skip_ws () =
    match peek () with
    | Some (' ' | '\t' | '\n' | '\r') ->
        advance ();
        skip_ws ()
    | _ -> ()
  in
  let expect c =
    skip_ws ();
    match peek () with
    | Some ch when ch = c -> advance ()
    | Some ch ->
        failwith (Printf.sprintf "expected '%c' got '%c' at %d" c ch !pos)
    | None -> failwith (Printf.sprintf "expected '%c' got EOF" c)
  in
  let rec parse_value () : Entity.value =
    skip_ws ();
    match peek () with
    | Some '"' -> Entity.String (parse_string ())
    | Some '{' ->
        (* nested object — store as string for now *)
        let start = !pos in
        ignore (parse_object_raw ());
        Entity.String (String.sub s start (!pos - start))
    | Some '[' -> Entity.List (parse_array ())
    | Some 't' ->
        (* true *)
        pos := !pos + 4;
        Entity.Bool true
    | Some 'f' ->
        (* false *)
        pos := !pos + 5;
        Entity.Bool false
    | Some 'n' ->
        (* null *)
        pos := !pos + 4;
        Entity.Null
    | Some c when c = '-' || (c >= '0' && c <= '9') -> parse_number ()
    | Some c -> failwith (Printf.sprintf "unexpected char '%c' at %d" c !pos)
    | None -> failwith "unexpected EOF"
  and parse_string () : string =
    expect '"';
    let buf = Buffer.create 32 in
    let rec loop () =
      match peek () with
      | Some '\\' -> (
          advance ();
          match peek () with
          | Some '"' ->
              Buffer.add_char buf '"';
              advance ();
              loop ()
          | Some '\\' ->
              Buffer.add_char buf '\\';
              advance ();
              loop ()
          | Some 'n' ->
              Buffer.add_char buf '\n';
              advance ();
              loop ()
          | Some c ->
              Buffer.add_char buf '\\';
              Buffer.add_char buf c;
              advance ();
              loop ()
          | None -> ())
      | Some '"' -> advance ()
      | Some c ->
          Buffer.add_char buf c;
          advance ();
          loop ()
      | None -> ()
    in
    loop ();
    Buffer.contents buf
  and parse_number () : Entity.value =
    let start = !pos in
    let is_float = ref false in
    let rec loop () =
      match peek () with
      | Some c when (c >= '0' && c <= '9') || c = '-' ->
          advance ();
          loop ()
      | Some '.' | Some 'e' | Some 'E' ->
          is_float := true;
          advance ();
          loop ()
      | _ -> ()
    in
    loop ();
    let raw = String.sub s start (!pos - start) in
    if !is_float then Entity.Float (float_of_string raw)
    else Entity.Int (int_of_string raw)
  and parse_array () : Entity.value list =
    expect '[';
    skip_ws ();
    match peek () with
    | Some ']' ->
        advance ();
        []
    | _ ->
        let items = ref [] in
        items := parse_value () :: !items;
        let rec loop () =
          skip_ws ();
          match peek () with
          | Some ',' ->
              advance ();
              items := parse_value () :: !items;
              loop ()
          | Some ']' -> advance ()
          | _ -> ()
        in
        loop ();
        List.rev !items
  and parse_object_raw () : unit =
    expect '{';
    let depth = ref 1 in
    while !depth > 0 do
      match peek () with
      | Some '{' ->
          incr depth;
          advance ()
      | Some '}' ->
          decr depth;
          advance ()
      | Some '"' ->
          advance ();
          let rec skip_str () =
            match peek () with
            | Some '\\' ->
                advance ();
                advance ();
                skip_str ()
            | Some '"' -> advance ()
            | Some _ ->
                advance ();
                skip_str ()
            | None -> ()
          in
          skip_str ()
      | Some _ -> advance ()
      | None -> depth := 0
    done
  in
  let parse_object () : Entity.data =
    expect '{';
    skip_ws ();
    match peek () with
    | Some '}' ->
        advance ();
        []
    | _ ->
        let pairs = ref [] in
        let parse_pair () =
          skip_ws ();
          let k = parse_string () in
          skip_ws ();
          expect ':';
          let v = parse_value () in
          pairs := (k, v) :: !pairs
        in
        parse_pair ();
        let rec loop () =
          skip_ws ();
          match peek () with
          | Some ',' ->
              advance ();
              parse_pair ();
              loop ()
          | Some '}' -> advance ()
          | _ -> ()
        in
        loop ();
        List.rev !pairs
  in
  try parse_object () with _ -> []

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
  try
    let db = Sqlite3.db_open path in
    ignore (Sqlite3.exec db "PRAGMA journal_mode=WAL;");
    ignore (Sqlite3.exec db "PRAGMA foreign_keys=ON;");
    match run_migrations db with
    | Ok () -> Ok { db }
    | Error e ->
        ignore (Sqlite3.db_close db);
        Error e
  with exn -> Error (Db_error (Printexc.to_string exn))

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

let query_entities t ?kind ?pattern () =
  let base = "SELECT id, lid, data, created, updated FROM entities WHERE 1=1" in
  let clauses = ref [] in
  let binds = ref [] in
  let bind_idx = ref 1 in
  (match kind with
  | Some k ->
      let idx = !bind_idx in
      clauses := Printf.sprintf " AND kind = ?%d" idx :: !clauses;
      binds :=
        (fun stmt ->
          ignore
            (Sqlite3.bind stmt idx (Sqlite3.Data.TEXT (Lid.prefix_of_kind k))))
        :: !binds;
      incr bind_idx
  | None -> ());
  (match pattern with
  | Some p ->
      let idx = !bind_idx in
      clauses := Printf.sprintf " AND path LIKE ?%d" idx :: !clauses;
      binds :=
        (fun stmt -> ignore (Sqlite3.bind stmt idx (Sqlite3.Data.TEXT p)))
        :: !binds;
      incr bind_idx
  | None -> ());
  let sql = base ^ String.concat "" (List.rev !clauses) ^ " ORDER BY lid" in
  let stmt = Sqlite3.prepare t.db sql in
  List.iter (fun f -> f stmt) (List.rev !binds);
  let results = ref [] in
  let rec loop () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        (match row_to_stored stmt with
        | Some e -> results := e :: !results
        | None -> ());
        loop ()
    | _ -> ()
  in
  loop ();
  ignore (Sqlite3.finalize stmt);
  Ok (List.rev !results)

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

let resolve_all t =
  (* Mark as resolved where both source and target entities exist *)
  let update_sql =
    "UPDATE refs SET resolved = 1 WHERE resolved = 0 AND source_lid IN (SELECT \
     lid FROM entities) AND target_lid IN (SELECT lid FROM entities)"
  in
  match exec_sql t.db update_sql with
  | Error e -> Error e
  | Ok () ->
      (* Fetch newly resolved *)
      let resolved_sql =
        "SELECT r.source_lid, r.target_lid, r.rel_type, es.id, et.id FROM refs \
         r JOIN entities es ON es.lid = r.source_lid JOIN entities et ON \
         et.lid = r.target_lid WHERE r.resolved = 1"
      in
      let stmt_r = Sqlite3.prepare t.db resolved_sql in
      let resolved = ref [] in
      let rec loop () =
        match Sqlite3.step stmt_r with
        | Sqlite3.Rc.ROW ->
            let src_lid_s =
              Sqlite3.Data.to_string_exn (Sqlite3.column stmt_r 0)
            in
            let tgt_lid_s =
              Sqlite3.Data.to_string_exn (Sqlite3.column stmt_r 1)
            in
            let rel_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt_r 2) in
            let src_id = Sqlite3.Data.to_int_exn (Sqlite3.column stmt_r 3) in
            let tgt_id = Sqlite3.Data.to_int_exn (Sqlite3.column stmt_r 4) in
            (match
               ( Lid.of_string src_lid_s,
                 Lid.of_string tgt_lid_s,
                 Ref.rel_of_string rel_s )
             with
            | Ok source, Ok target, Some rel ->
                resolved :=
                  Ref.
                    {
                      source;
                      target;
                      rel;
                      source_id = src_id;
                      target_id = tgt_id;
                    }
                  :: !resolved
            | _ -> ());
            loop ()
        | _ -> ()
      in
      loop ();
      ignore (Sqlite3.finalize stmt_r);
      (* Fetch still pending *)
      let pending_sql =
        "SELECT source_lid, target_lid, rel_type FROM refs WHERE resolved = 0"
      in
      let stmt_p = Sqlite3.prepare t.db pending_sql in
      let pending = ref [] in
      let rec loop2 () =
        match Sqlite3.step stmt_p with
        | Sqlite3.Rc.ROW ->
            let src_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt_p 0) in
            let tgt_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt_p 1) in
            let rel_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt_p 2) in
            (match
               ( Lid.of_string src_s,
                 Lid.of_string tgt_s,
                 Ref.rel_of_string rel_s )
             with
            | Ok source, Ok target, Some rel ->
                pending := Ref.{ source; target; rel } :: !pending
            | _ -> ());
            loop2 ()
        | _ -> ()
      in
      loop2 ();
      ignore (Sqlite3.finalize stmt_p);
      Ok (List.rev !resolved, List.rev !pending)

let query_refs t ?source ?target ?rel () =
  let base =
    "SELECT r.source_lid, r.target_lid, r.rel_type, es.id, et.id FROM refs r \
     JOIN entities es ON es.lid = r.source_lid JOIN entities et ON et.lid = \
     r.target_lid WHERE r.resolved = 1"
  in
  let clauses = ref [] in
  let binds = ref [] in
  let bind_idx = ref 1 in
  (match source with
  | Some s ->
      let idx = !bind_idx in
      clauses := Printf.sprintf " AND r.source_lid = ?%d" idx :: !clauses;
      binds :=
        (fun stmt ->
          ignore (Sqlite3.bind stmt idx (Sqlite3.Data.TEXT (Lid.to_string s))))
        :: !binds;
      incr bind_idx
  | None -> ());
  (match target with
  | Some tgt ->
      let idx = !bind_idx in
      clauses := Printf.sprintf " AND r.target_lid = ?%d" idx :: !clauses;
      binds :=
        (fun stmt ->
          ignore (Sqlite3.bind stmt idx (Sqlite3.Data.TEXT (Lid.to_string tgt))))
        :: !binds;
      incr bind_idx
  | None -> ());
  (match rel with
  | Some r ->
      let idx = !bind_idx in
      clauses := Printf.sprintf " AND r.rel_type = ?%d" idx :: !clauses;
      binds :=
        (fun stmt ->
          ignore
            (Sqlite3.bind stmt idx (Sqlite3.Data.TEXT (Ref.rel_to_string r))))
        :: !binds;
      incr bind_idx
  | None -> ());
  let sql = base ^ String.concat "" (List.rev !clauses) in
  let stmt = Sqlite3.prepare t.db sql in
  List.iter (fun f -> f stmt) (List.rev !binds);
  let results = ref [] in
  let rec loop () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        let src_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt 0) in
        let tgt_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt 1) in
        let rel_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt 2) in
        let src_id = Sqlite3.Data.to_int_exn (Sqlite3.column stmt 3) in
        let tgt_id = Sqlite3.Data.to_int_exn (Sqlite3.column stmt 4) in
        (match
           (Lid.of_string src_s, Lid.of_string tgt_s, Ref.rel_of_string rel_s)
         with
        | Ok source, Ok target, Some rel ->
            results :=
              Ref.
                { source; target; rel; source_id = src_id; target_id = tgt_id }
              :: !results
        | _ -> ());
        loop ()
    | _ -> ()
  in
  loop ();
  ignore (Sqlite3.finalize stmt);
  Ok (List.rev !results)

let pending_refs t =
  let sql =
    "SELECT source_lid, target_lid, rel_type FROM refs WHERE resolved = 0"
  in
  let stmt = Sqlite3.prepare t.db sql in
  let results = ref [] in
  let rec loop () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        let src_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt 0) in
        let tgt_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt 1) in
        let rel_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt 2) in
        (match
           (Lid.of_string src_s, Lid.of_string tgt_s, Ref.rel_of_string rel_s)
         with
        | Ok source, Ok target, Some rel ->
            results := Ref.{ source; target; rel } :: !results
        | _ -> ());
        loop ()
    | _ -> ()
  in
  loop ();
  ignore (Sqlite3.finalize stmt);
  Ok (List.rev !results)

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
  let sql, binds =
    match kind with
    | Some k ->
        ( "SELECT lid FROM entities WHERE kind = ? ORDER BY lid",
          [
            (fun stmt ->
              ignore
                (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT (Lid.prefix_of_kind k))));
          ] )
    | None -> ("SELECT lid FROM entities ORDER BY lid", [])
  in
  let stmt = Sqlite3.prepare t.db sql in
  List.iter (fun f -> f stmt) binds;
  let results = ref [] in
  let rec loop () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        let lid_s = Sqlite3.Data.to_string_exn (Sqlite3.column stmt 0) in
        (match Lid.of_string lid_s with
        | Ok lid -> results := lid :: !results
        | Error _ -> ());
        loop ()
    | _ -> ()
  in
  loop ();
  ignore (Sqlite3.finalize stmt);
  Ok (List.rev !results)
