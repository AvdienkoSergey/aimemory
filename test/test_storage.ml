open OUnit2

(* ------------------------------------------------------------------ *)
(*  Helpers                                                             *)
(* ------------------------------------------------------------------ *)

let open_mem _ctx =
  match Repo.open_db ":memory:" with
  | Ok db -> db
  | Error e -> assert_failure ("open_db failed: " ^ Repo.pp_error e)

let ok_or_fail = function
  | Ok v -> v
  | Error e -> assert_failure ("Unexpected error: " ^ Repo.pp_error e)

let make_raw lid_str ?(data = []) () =
  match Lid.of_string lid_str with
  | Ok lid -> Entity.{ lid; data }
  | Error _ -> assert_failure ("Invalid LID " ^ lid_str)

let make_pending src_str tgt_str rel =
  match (Lid.of_string src_str, Lid.of_string tgt_str) with
  | Ok source, Ok target -> Ref.{ source; target; rel }
  | _ -> assert_failure (Printf.sprintf "Invalid LIDs: %s / %s" src_str tgt_str)

(* ------------------------------------------------------------------ *)
(*  1. Lifecycle                                                        *)
(* ------------------------------------------------------------------ *)

let test_open_close _ctx =
  match Repo.open_db ":memory:" with
  | Error e -> assert_failure ("open_db failed: " ^ Repo.pp_error e)
  | Ok db -> Repo.close db

let test_with_db _ctx =
  let result = Repo.with_db ":memory:" (fun _db -> Ok "hello") in
  assert_equal (Ok "hello") result

let test_with_db_propagates_error _ctx =
  let result =
    Repo.with_db ":memory:" (fun _db -> Error (Repo.Db_error "intentional"))
  in
  match result with
  | Error (Repo.Db_error "intentional") -> ()
  | _ -> assert_failure "expected Db_error"

(* ------------------------------------------------------------------ *)
(*  2. pp_error                                                         *)
(* ------------------------------------------------------------------ *)

let test_pp_error_db_error _ctx =
  let s = Repo.pp_error (Repo.Db_error "oops") in
  assert_bool "contains 'oops'" (String.length s > 0)

let test_pp_error_not_found _ctx =
  let lid =
    match Lid.of_string "fn:foo" with
    | Ok l -> l
    | Error _ -> assert_failure "bad lid"
  in
  let s = Repo.pp_error (Repo.Not_found lid) in
  assert_bool "non-empty" (String.length s > 0)

(* ------------------------------------------------------------------ *)
(*  3. Entity upsert / find                                             *)
(* ------------------------------------------------------------------ *)

let test_upsert_insert _ctx =
  let db = open_mem _ctx in
  let raw = make_raw "fn:greet" ~data:[ ("name", Entity.String "Alice") ] () in
  let stored = ok_or_fail (Repo.upsert db raw) in
  assert_bool "id > 0" (stored.Entity.id > 0);
  assert_equal raw.Entity.lid stored.Entity.lid;
  Repo.close db

let test_upsert_update _ctx =
  let db = open_mem _ctx in
  let lid = "fn:greet" in
  let raw1 = make_raw lid ~data:[ ("v", Entity.Int 1) ] () in
  let raw2 = make_raw lid ~data:[ ("v", Entity.Int 2) ] () in
  let s1 = ok_or_fail (Repo.upsert db raw1) in
  let s2 = ok_or_fail (Repo.upsert db raw2) in
  assert_equal s1.Entity.id s2.Entity.id;
  assert_equal [ ("v", Entity.Int 2) ] s2.Entity.data;
  Repo.close db

let test_find_by_lid_existing _ctx =
  let db = open_mem _ctx in
  let raw = make_raw "fn:hello" () in
  let stored = ok_or_fail (Repo.upsert db raw) in
  (match ok_or_fail (Repo.find_by_lid db raw.Entity.lid) with
  | Some e -> assert_equal stored.Entity.id e.Entity.id
  | None -> assert_failure "entity not found");
  Repo.close db

let test_find_by_lid_missing _ctx =
  let db = open_mem _ctx in
  let lid =
    match Lid.of_string "fn:ghost" with
    | Ok l -> l
    | Error _ -> assert_failure "bad lid"
  in
  (match ok_or_fail (Repo.find_by_lid db lid) with
  | None -> ()
  | Some _ -> assert_failure "should be None");
  Repo.close db

let test_find_by_id _ctx =
  let db = open_mem _ctx in
  let raw = make_raw "fn:hi" () in
  let stored = ok_or_fail (Repo.upsert db raw) in
  (match ok_or_fail (Repo.find_by_id db stored.Entity.id) with
  | Some e -> assert_equal stored.Entity.lid e.Entity.lid
  | None -> assert_failure "not found by id");
  Repo.close db

let test_find_by_id_missing _ctx =
  let db = open_mem _ctx in
  (match ok_or_fail (Repo.find_by_id db 999999) with
  | None -> ()
  | Some _ -> assert_failure "should be None");
  Repo.close db

let test_upsert_many _ctx =
  let db = open_mem _ctx in
  let raws = [ make_raw "fn:a" (); make_raw "fn:b" (); make_raw "fn:c" () ] in
  let stored_list = ok_or_fail (Repo.upsert_many db raws) in
  assert_equal 3 (List.length stored_list);
  let ids = List.map (fun e -> e.Entity.id) stored_list in
  let uniq = List.sort_uniq compare ids in
  assert_equal 3 (List.length uniq);
  Repo.close db

(* ------------------------------------------------------------------ *)
(*  4. Entity query / delete                                            *)
(* ------------------------------------------------------------------ *)

let test_query_entities_all _ctx =
  let db = open_mem _ctx in
  ignore
    (ok_or_fail
       (Repo.upsert_many db [ make_raw "fn:x" (); make_raw "type:x" () ]));
  let all, _total = ok_or_fail (Repo.query_entities db ()) in
  assert_equal 2 (List.length all);
  Repo.close db

let test_query_entities_by_kind _ctx =
  let db = open_mem _ctx in
  ignore
    (ok_or_fail
       (Repo.upsert_many db
          [ make_raw "fn:foo" (); make_raw "fn:bar" (); make_raw "type:baz" () ]));
  let kind =
    match Lid.of_string "fn:dummy" with
    | Ok l -> Lid.kind l
    | Error _ -> assert_failure "bad lid"
  in
  let results, _total = ok_or_fail (Repo.query_entities db ~kind ()) in
  assert_equal 2 (List.length results);
  List.iter (fun e -> assert_equal kind (Lid.kind e.Entity.lid)) results;
  Repo.close db

let test_query_entities_by_pattern _ctx =
  let db = open_mem _ctx in
  ignore
    (ok_or_fail
       (Repo.upsert_many db
          [
            make_raw "fn:auth/login" ();
            make_raw "fn:auth/logout" ();
            make_raw "fn:home" ();
          ]));
  let results, _total =
    ok_or_fail (Repo.query_entities db ~pattern:"auth/%" ())
  in
  assert_equal 2 (List.length results);
  Repo.close db

let test_delete_existing _ctx =
  let db = open_mem _ctx in
  let raw = make_raw "fn:del" () in
  ignore (ok_or_fail (Repo.upsert db raw));
  let deleted = ok_or_fail (Repo.delete db raw.Entity.lid) in
  assert_bool "delete returned true" deleted;
  (match ok_or_fail (Repo.find_by_lid db raw.Entity.lid) with
  | None -> ()
  | Some _ -> assert_failure "entity still present after delete");
  Repo.close db

let test_delete_missing _ctx =
  let db = open_mem _ctx in
  let lid =
    match Lid.of_string "fn:nobody" with
    | Ok l -> l
    | Error _ -> assert_failure "bad lid"
  in
  let deleted = ok_or_fail (Repo.delete db lid) in
  assert_bool "delete of missing returns false" (not deleted);
  Repo.close db

(* ------------------------------------------------------------------ *)
(*  5. Entity data round-trip (encode -> decode)                       *)
(* ------------------------------------------------------------------ *)

let test_data_roundtrip_string _ctx =
  let db = open_mem _ctx in
  let raw =
    make_raw "fn:rt" ~data:[ ("greeting", Entity.String {|He said "hi"|}) ] ()
  in
  let stored = ok_or_fail (Repo.upsert db raw) in
  assert_equal raw.Entity.data stored.Entity.data;
  Repo.close db

let test_data_roundtrip_int _ctx =
  let db = open_mem _ctx in
  let raw = make_raw "fn:rt_int" ~data:[ ("count", Entity.Int 42) ] () in
  let stored = ok_or_fail (Repo.upsert db raw) in
  assert_equal [ ("count", Entity.Int 42) ] stored.Entity.data;
  Repo.close db

let test_data_roundtrip_float _ctx =
  let db = open_mem _ctx in
  let raw = make_raw "fn:rt_float" ~data:[ ("pi", Entity.Float 3.14) ] () in
  let stored = ok_or_fail (Repo.upsert db raw) in
  (match stored.Entity.data with
  | [ ("pi", Entity.Float f) ] ->
      assert_bool "float close" (abs_float (f -. 3.14) < 1e-9)
  | _ -> assert_failure "unexpected data");
  Repo.close db

let test_data_roundtrip_bool _ctx =
  let db = open_mem _ctx in
  let raw =
    make_raw "fn:rt_bool"
      ~data:[ ("ok", Entity.Bool true); ("nope", Entity.Bool false) ]
      ()
  in
  let stored = ok_or_fail (Repo.upsert db raw) in
  assert_equal raw.Entity.data stored.Entity.data;
  Repo.close db

let test_data_roundtrip_null _ctx =
  let db = open_mem _ctx in
  let raw = make_raw "fn:rt_null" ~data:[ ("nothing", Entity.Null) ] () in
  let stored = ok_or_fail (Repo.upsert db raw) in
  assert_equal [ ("nothing", Entity.Null) ] stored.Entity.data;
  Repo.close db

let test_data_roundtrip_list _ctx =
  let db = open_mem _ctx in
  let lst = Entity.List [ Entity.Int 1; Entity.Int 2; Entity.Int 3 ] in
  let raw = make_raw "fn:rt_list" ~data:[ ("nums", lst) ] () in
  let stored = ok_or_fail (Repo.upsert db raw) in
  assert_equal raw.Entity.data stored.Entity.data;
  Repo.close db

let test_data_empty _ctx =
  let db = open_mem _ctx in
  let raw = make_raw "fn:empty" ~data:[] () in
  let stored = ok_or_fail (Repo.upsert db raw) in
  assert_equal [] stored.Entity.data;
  Repo.close db

(* ------------------------------------------------------------------ *)
(*  6. Ref insert / pending                                             *)
(* ------------------------------------------------------------------ *)

let test_insert_ref_pending _ctx =
  let db = open_mem _ctx in
  let p = make_pending "fn:a" "fn:b" Ref.Calls in
  ignore (ok_or_fail (Repo.insert_ref db p));
  let pending = ok_or_fail (Repo.pending_refs db) in
  assert_equal 1 (List.length pending);
  let pr = List.hd pending in
  assert_equal p.Ref.source pr.Ref.source;
  assert_equal p.Ref.target pr.Ref.target;
  assert_equal p.Ref.rel pr.Ref.rel;
  Repo.close db

let test_insert_ref_idempotent _ctx =
  let db = open_mem _ctx in
  let p = make_pending "fn:a" "fn:b" Ref.Calls in
  ignore (ok_or_fail (Repo.insert_ref db p));
  ignore (ok_or_fail (Repo.insert_ref db p));
  let pending = ok_or_fail (Repo.pending_refs db) in
  assert_equal 1 (List.length pending);
  Repo.close db

let test_insert_refs_batch _ctx =
  let db = open_mem _ctx in
  let refs =
    [
      make_pending "fn:a" "fn:b" Ref.Calls;
      make_pending "fn:b" "fn:c" Ref.References;
    ]
  in
  ignore (ok_or_fail (Repo.insert_refs db refs));
  let pending = ok_or_fail (Repo.pending_refs db) in
  assert_equal 2 (List.length pending);
  Repo.close db

(* ------------------------------------------------------------------ *)
(*  7. Ref resolve                                                      *)
(* ------------------------------------------------------------------ *)

let test_resolve_all_both_exist _ctx =
  let db = open_mem _ctx in
  ignore (ok_or_fail (Repo.upsert db (make_raw "fn:a" ())));
  ignore (ok_or_fail (Repo.upsert db (make_raw "fn:b" ())));
  ignore
    (ok_or_fail (Repo.insert_ref db (make_pending "fn:a" "fn:b" Ref.Calls)));
  let resolved, pending = ok_or_fail (Repo.resolve_all db) in
  assert_equal 1 (List.length resolved);
  assert_equal 0 (List.length pending);
  let r = List.hd resolved in
  assert_bool "source_id set" (r.Ref.source_id > 0);
  assert_bool "target_id set" (r.Ref.target_id > 0);
  Repo.close db

let test_resolve_all_target_missing _ctx =
  let db = open_mem _ctx in
  ignore (ok_or_fail (Repo.upsert db (make_raw "fn:a" ())));
  ignore
    (ok_or_fail (Repo.insert_ref db (make_pending "fn:a" "fn:b" Ref.Calls)));
  let resolved, pending = ok_or_fail (Repo.resolve_all db) in
  assert_equal 0 (List.length resolved);
  assert_equal 1 (List.length pending);
  Repo.close db

let test_resolve_all_mixed _ctx =
  let db = open_mem _ctx in
  ignore (ok_or_fail (Repo.upsert db (make_raw "fn:x" ())));
  ignore (ok_or_fail (Repo.upsert db (make_raw "fn:y" ())));
  ignore
    (ok_or_fail (Repo.insert_ref db (make_pending "fn:x" "fn:y" Ref.Calls)));
  ignore
    (ok_or_fail
       (Repo.insert_ref db (make_pending "fn:x" "fn:z" Ref.References)));
  let resolved, pending = ok_or_fail (Repo.resolve_all db) in
  assert_equal 1 (List.length resolved);
  assert_equal 1 (List.length pending);
  Repo.close db

(* ------------------------------------------------------------------ *)
(*  8. Ref query                                                        *)
(* ------------------------------------------------------------------ *)

let setup_resolved_refs db =
  let la =
    match Lid.of_string "fn:a" with
    | Ok l -> l
    | Error _ -> assert_failure "bad"
  in
  let lb =
    match Lid.of_string "fn:b" with
    | Ok l -> l
    | Error _ -> assert_failure "bad"
  in
  let lc =
    match Lid.of_string "fn:c" with
    | Ok l -> l
    | Error _ -> assert_failure "bad"
  in
  ignore
    (ok_or_fail
       (Repo.upsert_many db
          [ make_raw "fn:a" (); make_raw "fn:b" (); make_raw "fn:c" () ]));
  ignore
    (ok_or_fail
       (Repo.insert_refs db
          [
            make_pending "fn:a" "fn:b" Ref.Calls;
            make_pending "fn:b" "fn:c" Ref.References;
            make_pending "fn:a" "fn:c" Ref.Calls;
          ]));
  ignore (ok_or_fail (Repo.resolve_all db));
  (la, lb, lc)

let test_query_refs_all _ctx =
  let db = open_mem _ctx in
  ignore (setup_resolved_refs db);
  let refs, _total = ok_or_fail (Repo.query_refs db ()) in
  assert_equal 3 (List.length refs);
  Repo.close db

let test_query_refs_by_source _ctx =
  let db = open_mem _ctx in
  let la, _lb, _lc = setup_resolved_refs db in
  let refs, _total = ok_or_fail (Repo.query_refs db ~source:la ()) in
  assert_equal 2 (List.length refs);
  List.iter (fun r -> assert_equal la r.Ref.source) refs;
  Repo.close db

let test_query_refs_by_target _ctx =
  let db = open_mem _ctx in
  let _la, _lb, lc = setup_resolved_refs db in
  let refs, _total = ok_or_fail (Repo.query_refs db ~target:lc ()) in
  assert_equal 2 (List.length refs);
  List.iter (fun r -> assert_equal lc r.Ref.target) refs;
  Repo.close db

let test_query_refs_by_rel _ctx =
  let db = open_mem _ctx in
  ignore (setup_resolved_refs db);
  let refs, _total = ok_or_fail (Repo.query_refs db ~rel:Ref.Calls ()) in
  assert_equal 2 (List.length refs);
  List.iter (fun r -> assert_equal Ref.Calls r.Ref.rel) refs;
  Repo.close db

let test_query_refs_combined _ctx =
  let db = open_mem _ctx in
  let la, _lb, lc = setup_resolved_refs db in
  let refs, _total = ok_or_fail (Repo.query_refs db ~source:la ~target:lc ()) in
  assert_equal 1 (List.length refs);
  Repo.close db

(* ------------------------------------------------------------------ *)
(*  9. Delete cascades to refs                                          *)
(* ------------------------------------------------------------------ *)

let test_delete_cascades_refs _ctx =
  let db = open_mem _ctx in
  ignore (ok_or_fail (Repo.upsert db (make_raw "fn:a" ())));
  ignore (ok_or_fail (Repo.upsert db (make_raw "fn:b" ())));
  ignore
    (ok_or_fail (Repo.insert_ref db (make_pending "fn:a" "fn:b" Ref.Calls)));
  let lid_a =
    match Lid.of_string "fn:a" with Ok l -> l | Error _ -> assert_failure ""
  in
  ignore (ok_or_fail (Repo.delete db lid_a));
  let pending = ok_or_fail (Repo.pending_refs db) in
  assert_equal 0 (List.length pending);
  Repo.close db

(* ------------------------------------------------------------------ *)
(*  10. Stats                                                           *)
(* ------------------------------------------------------------------ *)

let test_stats_empty _ctx =
  let db = open_mem _ctx in
  let s = ok_or_fail (Repo.stats db) in
  assert_equal 0 s.Repo.entity_count;
  assert_equal 0 s.Repo.ref_resolved_count;
  assert_equal 0 s.Repo.ref_pending_count;
  Repo.close db

let test_stats_after_ops _ctx =
  let db = open_mem _ctx in
  ignore
    (ok_or_fail
       (Repo.upsert_many db [ make_raw "fn:a" (); make_raw "fn:b" () ]));
  ignore
    (ok_or_fail (Repo.insert_ref db (make_pending "fn:a" "fn:b" Ref.Calls)));
  ignore
    (ok_or_fail
       (Repo.insert_ref db (make_pending "fn:a" "fn:z" Ref.References)));
  ignore (ok_or_fail (Repo.resolve_all db));
  let s = ok_or_fail (Repo.stats db) in
  assert_equal 2 s.Repo.entity_count;
  assert_equal 1 s.Repo.ref_resolved_count;
  assert_equal 1 s.Repo.ref_pending_count;
  Repo.close db

(* ------------------------------------------------------------------ *)
(*  11. all_lids                                                        *)
(* ------------------------------------------------------------------ *)

let test_all_lids _ctx =
  let db = open_mem _ctx in
  ignore
    (ok_or_fail
       (Repo.upsert_many db
          [ make_raw "fn:a" (); make_raw "fn:b" (); make_raw "type:x" () ]));
  let lids = ok_or_fail (Repo.all_lids db ()) in
  assert_equal 3 (List.length lids);
  Repo.close db

let test_all_lids_by_kind _ctx =
  let db = open_mem _ctx in
  ignore
    (ok_or_fail
       (Repo.upsert_many db
          [ make_raw "fn:a" (); make_raw "fn:b" (); make_raw "type:x" () ]));
  let kind =
    match Lid.of_string "fn:dummy" with
    | Ok l -> Lid.kind l
    | Error _ -> assert_failure "bad lid"
  in
  let lids = ok_or_fail (Repo.all_lids db ~kind ()) in
  assert_equal 2 (List.length lids);
  List.iter (fun lid -> assert_equal kind (Lid.kind lid)) lids;
  Repo.close db

(* ------------------------------------------------------------------ *)
(*  12. Pagination                                                      *)
(* ------------------------------------------------------------------ *)

let test_query_entities_with_limit _ctx =
  let db = open_mem _ctx in
  ignore
    (ok_or_fail
       (Repo.upsert_many db
          [
            make_raw "fn:a" ();
            make_raw "fn:b" ();
            make_raw "fn:c" ();
            make_raw "fn:d" ();
            make_raw "fn:e" ();
          ]));
  let results, total = ok_or_fail (Repo.query_entities db ~limit:3 ()) in
  assert_equal 3 (List.length results);
  assert_equal 5 total;
  Repo.close db

let test_query_entities_with_offset _ctx =
  let db = open_mem _ctx in
  ignore
    (ok_or_fail
       (Repo.upsert_many db
          [ make_raw "fn:a" (); make_raw "fn:b" (); make_raw "fn:c" () ]));
  (* offset requires limit in SQLite *)
  let results, total =
    ok_or_fail (Repo.query_entities db ~limit:10 ~offset:1 ())
  in
  assert_equal 2 (List.length results);
  assert_equal 3 total;
  Repo.close db

let test_query_entities_pagination _ctx =
  let db = open_mem _ctx in
  ignore
    (ok_or_fail
       (Repo.upsert_many db
          [
            make_raw "fn:a" ();
            make_raw "fn:b" ();
            make_raw "fn:c" ();
            make_raw "fn:d" ();
            make_raw "fn:e" ();
          ]));
  (* Page 1: first 2 items *)
  let page1, total1 =
    ok_or_fail (Repo.query_entities db ~limit:2 ~offset:0 ())
  in
  assert_equal 2 (List.length page1);
  assert_equal 5 total1;
  (* Page 2: next 2 items *)
  let page2, total2 =
    ok_or_fail (Repo.query_entities db ~limit:2 ~offset:2 ())
  in
  assert_equal 2 (List.length page2);
  assert_equal 5 total2;
  (* Page 3: last item *)
  let page3, total3 =
    ok_or_fail (Repo.query_entities db ~limit:2 ~offset:4 ())
  in
  assert_equal 1 (List.length page3);
  assert_equal 5 total3;
  Repo.close db

let test_query_refs_with_limit _ctx =
  let db = open_mem _ctx in
  ignore (setup_resolved_refs db);
  let refs, total = ok_or_fail (Repo.query_refs db ~limit:2 ()) in
  assert_equal 2 (List.length refs);
  assert_equal 3 total;
  Repo.close db

let test_query_refs_pagination _ctx =
  let db = open_mem _ctx in
  ignore (setup_resolved_refs db);
  let page1, _ = ok_or_fail (Repo.query_refs db ~limit:2 ~offset:0 ()) in
  assert_equal 2 (List.length page1);
  let page2, _ = ok_or_fail (Repo.query_refs db ~limit:2 ~offset:2 ()) in
  assert_equal 1 (List.length page2);
  Repo.close db

(* ------------------------------------------------------------------ *)
(*  13. Transactions                                                    *)
(* ------------------------------------------------------------------ *)

let test_with_tx_commit _ctx =
  let db = open_mem _ctx in
  ignore
    (ok_or_fail
       (Repo.with_tx db (fun db -> Repo.upsert db (make_raw "fn:tx" ()))));
  (match
     ok_or_fail
       (Repo.find_by_lid db
          (match Lid.of_string "fn:tx" with
          | Ok l -> l
          | Error _ -> assert_failure ""))
   with
  | Some _ -> ()
  | None -> assert_failure "entity not committed");
  Repo.close db

let test_with_tx_rollback _ctx =
  let db = open_mem _ctx in
  let lid =
    match Lid.of_string "fn:rollback" with
    | Ok l -> l
    | Error _ -> assert_failure ""
  in
  let _ =
    Repo.with_tx db (fun db ->
        let _ = Repo.upsert db (make_raw "fn:rollback" ()) in
        Error (Repo.Db_error "deliberate rollback"))
  in
  (match ok_or_fail (Repo.find_by_lid db lid) with
  | None -> ()
  | Some _ -> assert_failure "entity should have been rolled back");
  Repo.close db

(* ------------------------------------------------------------------ *)
(*  Suite assembly                                                      *)
(* ------------------------------------------------------------------ *)

let suite =
  "repo"
  >::: [
         "open_close" >:: test_open_close;
         "with_db_ok" >:: test_with_db;
         "with_db_error" >:: test_with_db_propagates_error;
         "pp_error_db" >:: test_pp_error_db_error;
         "pp_error_not_found" >:: test_pp_error_not_found;
         "upsert_insert" >:: test_upsert_insert;
         "upsert_update" >:: test_upsert_update;
         "find_by_lid_existing" >:: test_find_by_lid_existing;
         "find_by_lid_missing" >:: test_find_by_lid_missing;
         "find_by_id" >:: test_find_by_id;
         "find_by_id_missing" >:: test_find_by_id_missing;
         "upsert_many" >:: test_upsert_many;
         "query_entities_all" >:: test_query_entities_all;
         "query_entities_by_kind" >:: test_query_entities_by_kind;
         "query_entities_by_pattern" >:: test_query_entities_by_pattern;
         "delete_existing" >:: test_delete_existing;
         "delete_missing" >:: test_delete_missing;
         "roundtrip_string" >:: test_data_roundtrip_string;
         "roundtrip_int" >:: test_data_roundtrip_int;
         "roundtrip_float" >:: test_data_roundtrip_float;
         "roundtrip_bool" >:: test_data_roundtrip_bool;
         "roundtrip_null" >:: test_data_roundtrip_null;
         "roundtrip_list" >:: test_data_roundtrip_list;
         "roundtrip_empty" >:: test_data_empty;
         "insert_ref_pending" >:: test_insert_ref_pending;
         "insert_ref_idempotent" >:: test_insert_ref_idempotent;
         "insert_refs_batch" >:: test_insert_refs_batch;
         "resolve_both_exist" >:: test_resolve_all_both_exist;
         "resolve_target_missing" >:: test_resolve_all_target_missing;
         "resolve_mixed" >:: test_resolve_all_mixed;
         "query_refs_all" >:: test_query_refs_all;
         "query_refs_by_source" >:: test_query_refs_by_source;
         "query_refs_by_target" >:: test_query_refs_by_target;
         "query_refs_by_rel" >:: test_query_refs_by_rel;
         "query_refs_combined" >:: test_query_refs_combined;
         "delete_cascades_refs" >:: test_delete_cascades_refs;
         "stats_empty" >:: test_stats_empty;
         "stats_after_ops" >:: test_stats_after_ops;
         "all_lids" >:: test_all_lids;
         "all_lids_by_kind" >:: test_all_lids_by_kind;
         "query_entities_limit" >:: test_query_entities_with_limit;
         "query_entities_offset" >:: test_query_entities_with_offset;
         "query_entities_pagination" >:: test_query_entities_pagination;
         "query_refs_limit" >:: test_query_refs_with_limit;
         "query_refs_pagination" >:: test_query_refs_pagination;
         "tx_commit" >:: test_with_tx_commit;
         "tx_rollback" >:: test_with_tx_rollback;
       ]

let () = run_test_tt_main suite
