(** Unit tests for domain layer types: Lid, Entity, Ref, Protocol.
    Uses real modules from the domain library — no stubs. *)

open OUnit2

(* ── 1. Lid.of_string — valid cases ── *)

let test_lid_parse_valid_comp _ =
  match Lid.of_string "comp:ui/Button" with
  | Ok lid ->
      assert_equal Lid.Comp (Lid.kind lid);
      assert_equal "ui/Button" (Lid.path lid)
  | Error _ -> assert_failure "Expected Ok for 'comp:ui/Button'"

let test_lid_parse_valid_store _ =
  match Lid.of_string "store:auth" with
  | Ok lid ->
      assert_equal Lid.Store (Lid.kind lid);
      assert_equal "auth" (Lid.path lid)
  | Error _ -> assert_failure "Expected Ok for 'store:auth'"

let test_lid_parse_valid_type _ =
  match Lid.of_string "type:UserDto" with
  | Ok lid ->
      assert_equal Lid.Typ (Lid.kind lid);
      assert_equal "UserDto" (Lid.path lid)
  | Error _ -> assert_failure "Expected Ok for 'type:UserDto'"

let test_lid_parse_path_with_slashes _ =
  match Lid.of_string "fn:auth/login/validatePassword" with
  | Ok lid -> assert_equal "auth/login/validatePassword" (Lid.path lid)
  | Error _ -> assert_failure "Expected Ok for deep path"

(* ── 2. Lid.of_string — errors ── *)

let test_lid_parse_empty _ =
  assert_equal (Error Lid.Empty) (Lid.of_string "")

let test_lid_parse_missing_colon _ =
  assert_equal (Error Lid.Missing_colon) (Lid.of_string "compButton")

let test_lid_parse_unknown_kind _ =
  match Lid.of_string "widget:foo" with
  | Error (Lid.Unknown_kind "widget") -> ()
  | _ -> assert_failure "Expected Unknown_kind \"widget\""

let test_lid_parse_empty_path _ =
  assert_equal (Error Lid.Empty_path) (Lid.of_string "comp:")

(* ── 3. Lid.make + to_string — roundtrip ── *)

let test_lid_roundtrip _ =
  let lid = Lid.make Lid.Composable ~path:"useAuth" in
  assert_equal "composable:useAuth" (Lid.to_string lid)

let test_lid_roundtrip_all_kinds _ =
  List.iter
    (fun k ->
      let s = Lid.prefix_of_kind k ^ ":somepath" in
      match Lid.of_string s with
      | Ok lid -> assert_equal k (Lid.kind lid) ~msg:s
      | Error _ -> assert_failure ("Roundtrip failed for: " ^ s))
    Lid.all_kinds

(* ── 4. Lid equality ── *)

let test_lid_equal _ =
  let a = Lid.make Lid.Store ~path:"auth" in
  let b = Lid.make Lid.Store ~path:"auth" in
  assert_equal (Lid.to_string a) (Lid.to_string b)

let test_lid_not_equal_different_kind _ =
  let a = Lid.make Lid.Comp ~path:"auth" in
  let b = Lid.make Lid.Store ~path:"auth" in
  assert_bool "Different kinds must differ" (Lid.to_string a <> Lid.to_string b)

(* ── 5. Lid.Map и Lid.Set ── *)

let test_lid_map _ =
  let a = Lid.make Lid.Fn ~path:"doThing" in
  let b = Lid.make Lid.Fn ~path:"otherThing" in
  let m = Lid.Map.empty |> Lid.Map.add a 1 |> Lid.Map.add b 2 in
  assert_equal 1 (Lid.Map.find a m);
  assert_equal 2 (Lid.Map.find b m);
  assert_equal 2 (Lid.Map.cardinal m)

let test_lid_set_no_duplicates _ =
  let a = Lid.make Lid.Api ~path:"users" in
  let s = Lid.Set.empty |> Lid.Set.add a |> Lid.Set.add a in
  assert_equal 1 (Lid.Set.cardinal s)

(* ── 6. Entity.value ── *)

let test_entity_data_construction _ =
  let data : Entity.data =
    [
      ("name", Entity.String "Button");
      ("count", Entity.Int 42);
      ("ratio", Entity.Float 0.5);
      ("active", Entity.Bool true);
      ("tags", Entity.List [ Entity.String "ui"; Entity.String "form" ]);
      ("extra", Entity.Null);
    ]
  in
  assert_equal 6 (List.length data);
  (match List.assoc "name" data with
  | Entity.String s -> assert_equal "Button" s
  | _ -> assert_failure "Expected String");
  match List.assoc "tags" data with
  | Entity.List lst -> assert_equal 2 (List.length lst)
  | _ -> assert_failure "Expected List"

let test_entity_raw _ =
  let lid = Lid.make Lid.Comp ~path:"ui/Button" in
  let data = [ ("label", Entity.String "Click me") ] in
  let raw = Entity.{ lid; data } in
  assert_equal lid raw.lid;
  assert_equal data raw.data

let test_entity_processed_has_id _ =
  let lid = Lid.make Lid.Store ~path:"cart" in
  let processed =
    Entity.{ id = 7; lid; data = []; created = 1_000_000.0; updated = 1_000_001.0 }
  in
  assert_equal 7 processed.id;
  assert_bool "created <= updated" (processed.created <= processed.updated)

(* ── 7. Ref types ── *)

let test_ref_pending_construction _ =
  let src = Lid.make Lid.Fn ~path:"caller" in
  let tgt = Lid.make Lid.Fn ~path:"callee" in
  let pending = Ref.{ source = src; target = tgt; rel = Ref.Calls } in
  assert_equal src pending.source;
  assert_equal tgt pending.target;
  assert_equal Ref.Calls pending.rel

let test_ref_resolved_construction _ =
  let src = Lid.make Lid.Fn ~path:"caller" in
  let tgt = Lid.make Lid.Fn ~path:"callee" in
  let resolved = Ref.{
    source = src;
    target = tgt;
    rel = Ref.Calls;
    source_id = 1;
    target_id = 2;
  } in
  assert_equal 1 resolved.source_id;
  assert_equal 2 resolved.target_id

let test_ref_rel_to_string _ =
  assert_equal "calls" (Ref.rel_to_string Ref.Calls);
  assert_equal "belongs_to" (Ref.rel_to_string Ref.Belongs_to);
  assert_equal "depends_on" (Ref.rel_to_string Ref.Depends_on)

let test_ref_rel_of_string _ =
  assert_equal (Some Ref.Calls) (Ref.rel_of_string "calls");
  assert_equal (Some Ref.Belongs_to) (Ref.rel_of_string "belongs_to");
  assert_equal None (Ref.rel_of_string "unknown")

let test_ref_rel_roundtrip _ =
  let rels = [Ref.Belongs_to; Ref.Calls; Ref.Depends_on;
              Ref.Contains; Ref.Implements; Ref.References] in
  List.iter (fun rel ->
    let s = Ref.rel_to_string rel in
    assert_equal (Some rel) (Ref.rel_of_string s)
      ~msg:("Roundtrip failed for: " ^ s)
  ) rels

(* ── 8. Protocol ── *)

let test_protocol_emit_command _ =
  let lid = Lid.make Lid.Comp ~path:"ui/Modal" in
  let input =
    Protocol.{ lid; data = [ ("title", Entity.String "Hi") ]; refs = [] }
  in
  let cmd = Protocol.Emit { Protocol.entities = [ input ] } in
  match cmd with
  | Protocol.Emit p -> assert_equal 1 (List.length p.Protocol.entities)
  | _ -> assert_failure "Expected Emit command"

let test_protocol_emit_with_refs _ =
  let src = Lid.make Lid.Fn ~path:"submit" in
  let tgt = Lid.make Lid.Api ~path:"users/create" in
  let ref_in = Protocol.{ target = tgt; rel = Ref.Calls } in
  let input = Protocol.{ lid = src; data = []; refs = [ ref_in ] } in
  let cmd = Protocol.Emit { Protocol.entities = [ input ] } in
  match cmd with
  | Protocol.Emit p ->
      let refs = (List.hd p.Protocol.entities).Protocol.refs in
      assert_equal 1 (List.length refs);
      assert_equal Ref.Calls (List.hd refs).Protocol.rel
  | _ -> assert_failure "Expected Emit"

let test_protocol_query_entities_with_kind _ =
  let q = Protocol.{ kind = Some Lid.Store; pattern = None;
                     limit = None; offset = None } in
  let cmd = Protocol.Query_entities q in
  match cmd with
  | Protocol.Query_entities q -> assert_equal (Some Lid.Store) q.Protocol.kind
  | _ -> assert_failure "Expected Query_entities"

let test_protocol_query_refs _ =
  let src = Lid.make Lid.Fn ~path:"login" in
  let q = Protocol.{ source = Some src; target = None; rel_type = Some Ref.Calls;
                     limit = None; offset = None } in
  let cmd = Protocol.Query_refs q in
  match cmd with
  | Protocol.Query_refs q ->
      assert_equal (Some src) q.Protocol.source;
      assert_equal (Some Ref.Calls) q.Protocol.rel_type
  | _ -> assert_failure "Expected Query_refs"

let test_protocol_emit_result _ =
  let lid = Lid.make Lid.Comp ~path:"ui/Button" in
  let result = Protocol.{ upserted = [ lid ]; refs_resolved = []; refs_pending = [] } in
  let resp = Protocol.Emit_result result in
  match resp with
  | Protocol.Emit_result r ->
      assert_equal 1 (List.length r.Protocol.upserted);
      assert_equal lid (List.hd r.Protocol.upserted)
  | _ -> assert_failure "Expected Emit_result"

let test_protocol_error_invalid_lid _ =
  let err = Protocol.Error (Protocol.Invalid_lid ("bad::", Lid.Empty_path)) in
  match err with
  | Protocol.Error (Protocol.Invalid_lid (s, Lid.Empty_path)) ->
      assert_equal "bad::" s
  | _ -> assert_failure "Expected Invalid_lid error"

let test_protocol_error_storage _ =
  let err = Protocol.Error (Protocol.Storage_error "DB connection failed") in
  match err with
  | Protocol.Error (Protocol.Storage_error msg) ->
      assert_bool "Message non-empty" (String.length msg > 0)
  | _ -> assert_failure "Expected Storage_error"

(* ── 9. Roundtrip: to_string . of_string = id ── *)

let test_lid_of_string_to_string_identity _ =
  let cases = [
    "comp:ui/Button";
    "store:auth";
    "fn:utils/formatDate";
    "type:UserDto";
    "provide:theme";
    "e2e:login-flow";
  ] in
  List.iter (fun s ->
    match Lid.of_string s with
    | Ok lid ->
        assert_equal s (Lid.to_string lid) ~msg:("Identity failed: " ^ s)
    | Error _ -> assert_failure ("Parse failed: " ^ s)
  ) cases

(* ── Suite ── *)

let suite =
  "Domain logic"
  >::: [
         (* Lid parsing — valid *)
         "lid_parse_comp" >:: test_lid_parse_valid_comp;
         "lid_parse_store" >:: test_lid_parse_valid_store;
         "lid_parse_type" >:: test_lid_parse_valid_type;
         "lid_parse_deep_path" >:: test_lid_parse_path_with_slashes;
         (* Lid parsing — errors *)
         "lid_parse_empty" >:: test_lid_parse_empty;
         "lid_parse_missing_colon" >:: test_lid_parse_missing_colon;
         "lid_parse_unknown_kind" >:: test_lid_parse_unknown_kind;
         "lid_parse_empty_path" >:: test_lid_parse_empty_path;
         (* Lid make / roundtrip *)
         "lid_roundtrip" >:: test_lid_roundtrip;
         "lid_roundtrip_all_kinds" >:: test_lid_roundtrip_all_kinds;
         "lid_identity" >:: test_lid_of_string_to_string_identity;
         (* Lid equality *)
         "lid_equal" >:: test_lid_equal;
         "lid_not_equal_kind" >:: test_lid_not_equal_different_kind;
         (* Lid collections *)
         "lid_map" >:: test_lid_map;
         "lid_set_no_duplicates" >:: test_lid_set_no_duplicates;
         (* Entity *)
         "entity_data_construction" >:: test_entity_data_construction;
         "entity_raw" >:: test_entity_raw;
         "entity_processed_has_id" >:: test_entity_processed_has_id;
         (* Ref types *)
         "ref_pending_construction" >:: test_ref_pending_construction;
         "ref_resolved_construction" >:: test_ref_resolved_construction;
         "ref_rel_to_string" >:: test_ref_rel_to_string;
         "ref_rel_of_string" >:: test_ref_rel_of_string;
         "ref_rel_roundtrip" >:: test_ref_rel_roundtrip;
         (* Protocol *)
         "protocol_emit_command" >:: test_protocol_emit_command;
         "protocol_emit_with_refs" >:: test_protocol_emit_with_refs;
         "protocol_query_entities" >:: test_protocol_query_entities_with_kind;
         "protocol_query_refs" >:: test_protocol_query_refs;
         "protocol_emit_result" >:: test_protocol_emit_result;
         "protocol_error_invalid_lid" >:: test_protocol_error_invalid_lid;
         "protocol_error_storage" >:: test_protocol_error_storage;
       ]

let () = run_test_tt_main suite
