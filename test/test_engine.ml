open OUnit2

let open_mem _ctx =
  match Repo.open_db ":memory:" with
  | Ok db -> db
  | Error e -> assert_failure ("open_db failed: " ^ Repo.pp_error e)

let lid_of_string s =
  match Lid.of_string s with
  | Ok lid -> lid
  | Error _ -> assert_failure ("Invalid LID: " ^ s)

let make_input lid_str ?(data = []) ?(refs = []) () =
  let lid = lid_of_string lid_str in
  let ref_inputs = List.map (fun (tgt, rel) ->
    Protocol.{ target = lid_of_string tgt; rel }
  ) refs in
  Protocol.{ lid; data; refs = ref_inputs }

let emit_result_of_response = function
  | Protocol.Emit_result r -> r
  | Protocol.Error e ->
    (match e with
     | Protocol.Storage_error s -> assert_failure ("Storage error: " ^ s)
     | _ -> assert_failure "Unexpected protocol error")
  | _ -> assert_failure "Expected Emit_result"

let entities_of_response = function
  | Protocol.Entities es -> es
  | Protocol.Error e ->
    (match e with
     | Protocol.Storage_error s -> assert_failure ("Storage error: " ^ s)
     | _ -> assert_failure "Unexpected protocol error")
  | _ -> assert_failure "Expected Entities"

let refs_of_response = function
  | Protocol.Refs rs -> rs
  | Protocol.Error e ->
    (match e with
     | Protocol.Storage_error s -> assert_failure ("Storage error: " ^ s)
     | _ -> assert_failure "Unexpected protocol error")
  | _ -> assert_failure "Expected Refs"


(* ------------------------------------------------------------------ *)
(*  Ingest: emit_one                                                   *)
(* ------------------------------------------------------------------ *)

let test_emit_one_simple _ctx =
  let db = open_mem _ctx in
  let lid = lid_of_string "fn:hello" in
  let resp = Ingest.emit_one db ~lid ~data:[("msg", Entity.String "hi")] in
  let result = emit_result_of_response resp in
  assert_equal 1 (List.length result.upserted);
  assert_equal lid (List.hd result.upserted);
  Repo.close db

let test_emit_one_updates _ctx =
  let db = open_mem _ctx in
  let lid = lid_of_string "fn:counter" in
  let _ = Ingest.emit_one db ~lid ~data:[("v", Entity.Int 1)] in
  let _ = Ingest.emit_one db ~lid ~data:[("v", Entity.Int 2)] in
  let resp = Ingest.query_by_kind db Lid.Fn in
  let entities = entities_of_response resp in
  assert_equal 1 (List.length entities);
  assert_equal [("v", Entity.Int 2)] (List.hd entities).Entity.data;
  Repo.close db


(* ------------------------------------------------------------------ *)
(*  Ingest: emit_with_refs                                             *)
(* ------------------------------------------------------------------ *)

let test_emit_with_refs_pending _ctx =
  let db = open_mem _ctx in
  let lid = lid_of_string "fn:caller" in
  let refs = [(lid_of_string "fn:callee", Ref.Calls)] in
  let resp = Ingest.emit_with_refs db ~lid ~data:[] ~refs in
  let result = emit_result_of_response resp in
  assert_equal 1 (List.length result.upserted);
  assert_equal 0 (List.length result.refs_resolved);
  assert_equal 1 (List.length result.refs_pending);
  Repo.close db

let test_emit_with_refs_resolved _ctx =
  let db = open_mem _ctx in
  let callee_lid = lid_of_string "fn:callee" in
  let _ = Ingest.emit_one db ~lid:callee_lid ~data:[] in
  let caller_lid = lid_of_string "fn:caller" in
  let refs = [(callee_lid, Ref.Calls)] in
  let resp = Ingest.emit_with_refs db ~lid:caller_lid ~data:[] ~refs in
  let result = emit_result_of_response resp in
  assert_equal 1 (List.length result.refs_resolved);
  assert_equal 0 (List.length result.refs_pending);
  Repo.close db


(* ------------------------------------------------------------------ *)
(*  Ingest: batch emit via process                                     *)
(* ------------------------------------------------------------------ *)

let test_process_emit_batch _ctx =
  let db = open_mem _ctx in
  let inputs = [
    make_input "fn:a" ~data:[("x", Entity.Int 1)] ();
    make_input "fn:b" ~data:[("y", Entity.Int 2)]
      ~refs:[("fn:a", Ref.Calls)] ();
  ] in
  let cmd = Protocol.Emit { entities = inputs } in
  let resp = Ingest.process db cmd in
  let result = emit_result_of_response resp in
  assert_equal 2 (List.length result.upserted);
  assert_equal 1 (List.length result.refs_resolved);
  Repo.close db


(* ------------------------------------------------------------------ *)
(*  Ingest: query commands                                             *)
(* ------------------------------------------------------------------ *)

let test_query_entities_by_kind _ctx =
  let db = open_mem _ctx in
  let _ = Ingest.emit_one db ~lid:(lid_of_string "fn:foo") ~data:[] in
  let _ = Ingest.emit_one db ~lid:(lid_of_string "fn:bar") ~data:[] in
  let _ = Ingest.emit_one db ~lid:(lid_of_string "comp:baz") ~data:[] in
  let resp = Ingest.query_by_kind db Lid.Fn in
  let entities = entities_of_response resp in
  assert_equal 2 (List.length entities);
  Repo.close db

let test_query_entities_by_pattern _ctx =
  let db = open_mem _ctx in
  let _ = Ingest.emit_one db ~lid:(lid_of_string "fn:auth/login") ~data:[] in
  let _ = Ingest.emit_one db ~lid:(lid_of_string "fn:auth/logout") ~data:[] in
  let _ = Ingest.emit_one db ~lid:(lid_of_string "fn:home") ~data:[] in
  let resp = Ingest.query_by_pattern db "auth/*" in
  let entities = entities_of_response resp in
  assert_equal 2 (List.length entities);
  Repo.close db

let test_outgoing_refs _ctx =
  let db = open_mem _ctx in
  let lid_a = lid_of_string "fn:a" in
  let lid_b = lid_of_string "fn:b" in
  let lid_c = lid_of_string "fn:c" in
  let _ = Ingest.emit_one db ~lid:lid_a ~data:[] in
  let _ = Ingest.emit_one db ~lid:lid_b ~data:[] in
  let _ = Ingest.emit_one db ~lid:lid_c ~data:[] in
  let _ = Ingest.emit_with_refs db ~lid:lid_a ~data:[]
      ~refs:[(lid_b, Ref.Calls); (lid_c, Ref.References)] in
  let resp = Ingest.outgoing_refs db lid_a in
  let refs = refs_of_response resp in
  assert_equal 2 (List.length refs);
  Repo.close db

let test_incoming_refs _ctx =
  let db = open_mem _ctx in
  let target = lid_of_string "fn:target" in
  let _ = Ingest.emit_one db ~lid:target ~data:[] in
  let _ = Ingest.emit_with_refs db
      ~lid:(lid_of_string "fn:src1") ~data:[]
      ~refs:[(target, Ref.Calls)] in
  let _ = Ingest.emit_with_refs db
      ~lid:(lid_of_string "fn:src2") ~data:[]
      ~refs:[(target, Ref.References)] in
  let resp = Ingest.incoming_refs db target in
  let refs = refs_of_response resp in
  assert_equal 2 (List.length refs);
  Repo.close db


(* ------------------------------------------------------------------ *)
(*  Ingest: batch processing                                           *)
(* ------------------------------------------------------------------ *)

let test_process_batch_stops_on_error _ctx =
  let db = open_mem _ctx in
  let _ = Ingest.emit_one db ~lid:(lid_of_string "fn:a") ~data:[] in
  let _ = Ingest.emit_with_refs db
      ~lid:(lid_of_string "fn:b") ~data:[]
      ~refs:[(lid_of_string "fn:missing", Ref.Calls)] in
  let cmds = [
    Protocol.Query_refs { source = None; target = None; rel_type = None };
    Protocol.Query_entities { kind = None; pattern = None };
  ] in
  let responses = Ingest.process_batch db cmds in
  assert_equal 2 (List.length responses);
  Repo.close db

let test_process_all_collects_all _ctx =
  let db = open_mem _ctx in
  let _ = Ingest.emit_one db ~lid:(lid_of_string "fn:x") ~data:[] in
  let cmds = [
    Protocol.Emit { entities = [make_input "fn:y" ()] };
    Protocol.Query_entities { kind = Some Lid.Fn; pattern = None };
  ] in
  let responses = Ingest.process_all db cmds in
  assert_equal 2 (List.length responses);
  Repo.close db


(* ------------------------------------------------------------------ *)
(*  Ingest: status and diagnostics                                     *)
(* ------------------------------------------------------------------ *)

let test_status_empty _ctx =
  let db = open_mem _ctx in
  match Ingest.status db with
  | Ok s ->
    assert_equal 0 s.Ingest.stats.entity_count;
    assert_equal 0 s.Ingest.stats.ref_resolved_count;
    assert_equal 0 s.Ingest.stats.ref_pending_count;
    Repo.close db
  | Error e ->
    Repo.close db;
    assert_failure (Repo.pp_error e)

let test_status_after_ops _ctx =
  let db = open_mem _ctx in
  let lid_a = lid_of_string "fn:a" in
  let lid_missing = lid_of_string "fn:missing" in
  let _ = Ingest.emit_one db ~lid:lid_a ~data:[] in
  let _ = Ingest.emit_with_refs db
      ~lid:(lid_of_string "fn:b") ~data:[]
      ~refs:[(lid_a, Ref.Calls); (lid_missing, Ref.References)] in
  match Ingest.status db with
  | Ok s ->
    assert_equal 2 s.Ingest.stats.entity_count;
    assert_equal 1 s.Ingest.stats.ref_resolved_count;
    assert_equal 1 s.Ingest.stats.ref_pending_count;
    assert_equal 1 s.Ingest.missing.total_pending;
    Repo.close db
  | Error e ->
    Repo.close db;
    assert_failure (Repo.pp_error e)


(* ------------------------------------------------------------------ *)
(*  Resolver: glob_matches                                             *)
(* ------------------------------------------------------------------ *)

let test_glob_matches_exact _ctx =
  assert_bool "exact match" (Resolver.glob_matches ~pattern:"hello" "hello");
  assert_bool "exact no match" (not (Resolver.glob_matches ~pattern:"hello" "world"))

let test_glob_matches_star _ctx =
  assert_bool "* matches all" (Resolver.glob_matches ~pattern:"*" "anything");
  assert_bool "* matches empty" (Resolver.glob_matches ~pattern:"*" "")

let test_glob_matches_prefix _ctx =
  assert_bool "auth/* matches auth/login"
    (Resolver.glob_matches ~pattern:"auth/*" "auth/login");
  assert_bool "auth/* matches auth/"
    (Resolver.glob_matches ~pattern:"auth/*" "auth/");
  assert_bool "auth/* no match home"
    (not (Resolver.glob_matches ~pattern:"auth/*" "home"))

let test_glob_matches_suffix _ctx =
  assert_bool "*.ts matches file.ts"
    (Resolver.glob_matches ~pattern:"*.ts" "file.ts");
  assert_bool "*.ts no match file.js"
    (not (Resolver.glob_matches ~pattern:"*.ts" "file.js"))


(* ------------------------------------------------------------------ *)
(*  Resolver: resolve_pending                                          *)
(* ------------------------------------------------------------------ *)

let test_resolve_pending_all_exist _ctx =
  let db = open_mem _ctx in
  let lid_a = lid_of_string "fn:a" in
  let lid_b = lid_of_string "fn:b" in
  let _ = Ingest.emit_one db ~lid:lid_a ~data:[] in
  let _ = Ingest.emit_one db ~lid:lid_b ~data:[] in
  let pending = [Ref.{ source = lid_a; target = lid_b; rel = Ref.Calls }] in
  match Resolver.resolve_pending db pending with
  | Ok result ->
    assert_equal 1 (List.length result.resolved);
    assert_equal 0 (List.length result.pending);
    Repo.close db
  | Error e ->
    Repo.close db;
    assert_failure (Repo.pp_error e)

let test_resolve_pending_target_missing _ctx =
  let db = open_mem _ctx in
  let lid_a = lid_of_string "fn:a" in
  let _ = Ingest.emit_one db ~lid:lid_a ~data:[] in
  let pending = [Ref.{
    source = lid_a;
    target = lid_of_string "fn:missing";
    rel = Ref.Calls
  }] in
  match Resolver.resolve_pending db pending with
  | Ok result ->
    assert_equal 0 (List.length result.resolved);
    assert_equal 1 (List.length result.pending);
    Repo.close db
  | Error e ->
    Repo.close db;
    assert_failure (Repo.pp_error e)


(* ------------------------------------------------------------------ *)
(*  Resolver: analyze_pending                                          *)
(* ------------------------------------------------------------------ *)

let test_analyze_pending_empty _ctx =
  let db = open_mem _ctx in
  match Resolver.analyze_pending db with
  | Ok analysis ->
    assert_equal 0 analysis.total_pending;
    assert_equal 0 (List.length analysis.missing_lids);
    Repo.close db
  | Error e ->
    Repo.close db;
    assert_failure (Repo.pp_error e)

let test_analyze_pending_missing _ctx =
  let db = open_mem _ctx in
  let missing1 = lid_of_string "fn:missing1" in
  let missing2 = lid_of_string "fn:missing2" in
  let _ = Ingest.emit_with_refs db
      ~lid:(lid_of_string "fn:a") ~data:[]
      ~refs:[(missing1, Ref.Calls); (missing2, Ref.References)] in
  let _ = Ingest.emit_with_refs db
      ~lid:(lid_of_string "fn:b") ~data:[]
      ~refs:[(missing1, Ref.Calls)] in
  match Resolver.analyze_pending db with
  | Ok analysis ->
    assert_equal 3 analysis.total_pending;
    assert_equal 2 (List.length analysis.missing_lids);
    let missing1_count = List.assoc_opt missing1 analysis.missing_lids in
    assert_equal (Some 2) missing1_count;
    Repo.close db
  | Error e ->
    Repo.close db;
    assert_failure (Repo.pp_error e)


(* ------------------------------------------------------------------ *)
(*  Suite                                                              *)
(* ------------------------------------------------------------------ *)

let suite =
  "engine" >::: [
    "emit_one_simple" >:: test_emit_one_simple;
    "emit_one_updates" >:: test_emit_one_updates;
    "emit_with_refs_pending" >:: test_emit_with_refs_pending;
    "emit_with_refs_resolved" >:: test_emit_with_refs_resolved;
    "process_emit_batch" >:: test_process_emit_batch;
    "query_entities_by_kind" >:: test_query_entities_by_kind;
    "query_entities_by_pattern" >:: test_query_entities_by_pattern;
    "outgoing_refs" >:: test_outgoing_refs;
    "incoming_refs" >:: test_incoming_refs;
    "process_batch_stops" >:: test_process_batch_stops_on_error;
    "process_all_collects" >:: test_process_all_collects_all;
    "status_empty" >:: test_status_empty;
    "status_after_ops" >:: test_status_after_ops;
    "glob_exact" >:: test_glob_matches_exact;
    "glob_star" >:: test_glob_matches_star;
    "glob_prefix" >:: test_glob_matches_prefix;
    "glob_suffix" >:: test_glob_matches_suffix;
    "resolve_pending_all_exist" >:: test_resolve_pending_all_exist;
    "resolve_pending_target_missing" >:: test_resolve_pending_target_missing;
    "analyze_pending_empty" >:: test_analyze_pending_empty;
    "analyze_pending_missing" >:: test_analyze_pending_missing;
  ]

let () = run_test_tt_main suite
