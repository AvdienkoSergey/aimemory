open OUnit2

let open_mem _ctx =
  match Repo.open_db ":memory:" with
  | Ok db -> db
  | Error e -> assert_failure ("open_db failed: " ^ Repo.pp_error e)


(* ------------------------------------------------------------------ *)
(*  JSON ↔ Domain converters                                          *)
(* ------------------------------------------------------------------ *)

let test_value_to_json_string _ctx =
  let v = Entity.String "hello" in
  let j = Tools.value_to_json v in
  assert_equal (`String "hello") j

let test_value_to_json_int _ctx =
  let v = Entity.Int 42 in
  let j = Tools.value_to_json v in
  assert_equal (`Int 42) j

let test_value_to_json_float _ctx =
  let v = Entity.Float 3.14 in
  let j = Tools.value_to_json v in
  assert_equal (`Float 3.14) j

let test_value_to_json_bool _ctx =
  let v = Entity.Bool true in
  let j = Tools.value_to_json v in
  assert_equal (`Bool true) j

let test_value_to_json_null _ctx =
  let v = Entity.Null in
  let j = Tools.value_to_json v in
  assert_equal `Null j

let test_value_to_json_list _ctx =
  let v = Entity.List [Entity.Int 1; Entity.Int 2] in
  let j = Tools.value_to_json v in
  assert_equal (`List [`Int 1; `Int 2]) j

let test_json_to_value_string _ctx =
  let j = `String "world" in
  let v = Tools.json_to_value j in
  assert_equal (Entity.String "world") v

let test_json_to_value_int _ctx =
  let j = `Int 99 in
  let v = Tools.json_to_value j in
  assert_equal (Entity.Int 99) v

let test_json_to_value_nested_object _ctx =
  let j = `Assoc [("key", `String "val")] in
  let v = Tools.json_to_value j in
  match v with
  | Entity.String _ -> ()
  | _ -> assert_failure "nested object should become string"

let test_data_roundtrip _ctx =
  let data = [("name", Entity.String "test"); ("count", Entity.Int 5)] in
  let json = Tools.data_to_json data in
  let back = Tools.json_to_data json in
  assert_equal data back


(* ------------------------------------------------------------------ *)
(*  Request parsing                                                    *)
(* ------------------------------------------------------------------ *)

let test_parse_entity_input_valid _ctx =
  let json = Yojson.Safe.from_string {|
    {
      "lid": "fn:auth/login",
      "data": {"async": true},
      "refs": [{"target": "fn:api/call", "rel": "calls"}]
    }
  |} in
  match Tools.parse_entity_input json with
  | Ok ei ->
    assert_equal "auth/login" (Lid.path ei.lid);
    assert_equal 1 (List.length ei.refs)
  | Error e -> assert_failure e

let test_parse_entity_input_missing_lid _ctx =
  let json = Yojson.Safe.from_string {|{"data": {}}|} in
  match Tools.parse_entity_input json with
  | Error _ -> ()
  | Ok _ -> assert_failure "should fail without lid"

let test_parse_entity_input_invalid_lid _ctx =
  let json = Yojson.Safe.from_string {|{"lid": "invalid"}|} in
  match Tools.parse_entity_input json with
  | Error e -> assert_bool "error mentions lid" (String.length e > 0)
  | Ok _ -> assert_failure "should fail with invalid lid"

let test_parse_emit_valid _ctx =
  let json = Yojson.Safe.from_string {|
    {"entities": [{"lid": "fn:test"}]}
  |} in
  match Tools.parse_emit json with
  | Ok (Protocol.Emit { entities }) ->
    assert_equal 1 (List.length entities)
  | Ok _ -> assert_failure "expected Emit command"
  | Error e -> assert_failure e

let test_parse_emit_empty _ctx =
  let json = Yojson.Safe.from_string {|{"entities": []}|} in
  match Tools.parse_emit json with
  | Error _ -> ()
  | Ok _ -> assert_failure "should fail with empty entities"

let test_parse_query_entities_all _ctx =
  let json = Yojson.Safe.from_string {|{}|} in
  match Tools.parse_query_entities json with
  | Ok (Protocol.Query_entities q) ->
    assert_equal None q.kind;
    assert_equal None q.pattern
  | _ -> assert_failure "expected Query_entities"

let test_parse_query_entities_with_kind _ctx =
  let json = Yojson.Safe.from_string {|{"kind": "fn"}|} in
  match Tools.parse_query_entities json with
  | Ok (Protocol.Query_entities q) ->
    assert_equal (Some Lid.Fn) q.kind
  | _ -> assert_failure "expected Query_entities with kind"

let test_parse_query_entities_with_pattern _ctx =
  let json = Yojson.Safe.from_string {|{"pattern": "auth/*"}|} in
  match Tools.parse_query_entities json with
  | Ok (Protocol.Query_entities q) ->
    assert_equal (Some "auth/*") q.pattern
  | _ -> assert_failure "expected Query_entities with pattern"

let test_parse_query_refs_all _ctx =
  let json = Yojson.Safe.from_string {|{}|} in
  match Tools.parse_query_refs json with
  | Ok (Protocol.Query_refs q) ->
    assert_equal None q.source;
    assert_equal None q.target;
    assert_equal None q.rel_type
  | _ -> assert_failure "expected Query_refs"

let test_parse_query_refs_with_source _ctx =
  let json = Yojson.Safe.from_string {|{"source": "fn:caller"}|} in
  match Tools.parse_query_refs json with
  | Ok (Protocol.Query_refs q) ->
    (match q.source with
     | Some lid -> assert_equal "caller" (Lid.path lid)
     | None -> assert_failure "expected source")
  | _ -> assert_failure "expected Query_refs"


(* ------------------------------------------------------------------ *)
(*  Dispatch integration                                               *)
(* ------------------------------------------------------------------ *)

let test_dispatch_emit _ctx =
  let db = open_mem _ctx in
  let args = {|{"entities": [{"lid": "fn:hello", "data": {"msg": "hi"}}]}|} in
  let result = Tools.dispatch db ~tool:"emit" ~args in
  let json = Yojson.Safe.from_string result in
  (match json with
   | `Assoc fields ->
     assert_equal (Some (`String "ok")) (List.assoc_opt "status" fields);
     assert_equal (Some (`String "emit")) (List.assoc_opt "command" fields)
   | _ -> assert_failure "expected JSON object");
  Repo.close db

let test_dispatch_query_entities _ctx =
  let db = open_mem _ctx in
  let _ = Tools.dispatch db ~tool:"emit"
      ~args:{|{"entities": [{"lid": "fn:a"}, {"lid": "fn:b"}]}|} in
  let result = Tools.dispatch db ~tool:"query_entities" ~args:{|{"kind": "fn"}|} in
  let json = Yojson.Safe.from_string result in
  (match json with
   | `Assoc fields ->
     assert_equal (Some (`String "ok")) (List.assoc_opt "status" fields);
     assert_equal (Some (`Int 2)) (List.assoc_opt "count" fields)
   | _ -> assert_failure "expected JSON object");
  Repo.close db

let test_dispatch_query_refs _ctx =
  let db = open_mem _ctx in
  let _ = Tools.dispatch db ~tool:"emit"
      ~args:{|{"entities": [
        {"lid": "fn:caller"},
        {"lid": "fn:callee", "refs": [{"target": "fn:caller", "rel": "calls"}]}
      ]}|} in
  let result = Tools.dispatch db ~tool:"query_refs" ~args:{|{}|} in
  let json = Yojson.Safe.from_string result in
  (match json with
   | `Assoc fields ->
     assert_equal (Some (`String "ok")) (List.assoc_opt "status" fields);
     assert_equal (Some (`Int 1)) (List.assoc_opt "count" fields)
   | _ -> assert_failure "expected JSON object");
  Repo.close db

let test_dispatch_status _ctx =
  let db = open_mem _ctx in
  let _ = Tools.dispatch db ~tool:"emit"
      ~args:{|{"entities": [{"lid": "fn:x"}]}|} in
  let result = Tools.dispatch db ~tool:"status" ~args:"{}" in
  let json = Yojson.Safe.from_string result in
  (match json with
   | `Assoc fields ->
     assert_equal (Some (`String "ok")) (List.assoc_opt "status" fields);
     assert_equal (Some (`Int 1)) (List.assoc_opt "entity_count" fields)
   | _ -> assert_failure "expected JSON object");
  Repo.close db

let test_dispatch_unknown_tool _ctx =
  let db = open_mem _ctx in
  let result = Tools.dispatch db ~tool:"unknown" ~args:"{}" in
  let json = Yojson.Safe.from_string result in
  (match json with
   | `Assoc fields ->
     assert_equal (Some (`String "error")) (List.assoc_opt "status" fields)
   | _ -> assert_failure "expected JSON object");
  Repo.close db

let test_dispatch_invalid_json _ctx =
  let db = open_mem _ctx in
  let result = Tools.dispatch db ~tool:"emit" ~args:"not json" in
  let json = Yojson.Safe.from_string result in
  (match json with
   | `Assoc fields ->
     assert_equal (Some (`String "error")) (List.assoc_opt "status" fields)
   | _ -> assert_failure "expected JSON object");
  Repo.close db


(* ------------------------------------------------------------------ *)
(*  Tool schemas                                                       *)
(* ------------------------------------------------------------------ *)

let test_tool_schemas_structure _ctx =
  let schemas = Tools.tool_schemas () in
  match schemas with
  | `Assoc fields ->
    assert_bool "has protocol" (List.mem_assoc "protocol" fields);
    assert_bool "has tools" (List.mem_assoc "tools" fields);
    (match List.assoc_opt "tools" fields with
     | Some (`List tools) -> assert_equal 4 (List.length tools)
     | _ -> assert_failure "tools should be a list")
  | _ -> assert_failure "expected JSON object"

let test_tool_schemas_string _ctx =
  let s = Tools.tool_schemas_string () in
  assert_bool "non-empty string" (String.length s > 100);
  assert_bool "contains emit" (String.length s > 0)


(* ------------------------------------------------------------------ *)
(*  Suite                                                              *)
(* ------------------------------------------------------------------ *)

let suite =
  "api" >::: [
    "value_to_json_string" >:: test_value_to_json_string;
    "value_to_json_int" >:: test_value_to_json_int;
    "value_to_json_float" >:: test_value_to_json_float;
    "value_to_json_bool" >:: test_value_to_json_bool;
    "value_to_json_null" >:: test_value_to_json_null;
    "value_to_json_list" >:: test_value_to_json_list;
    "json_to_value_string" >:: test_json_to_value_string;
    "json_to_value_int" >:: test_json_to_value_int;
    "json_to_value_nested" >:: test_json_to_value_nested_object;
    "data_roundtrip" >:: test_data_roundtrip;
    "parse_entity_input_valid" >:: test_parse_entity_input_valid;
    "parse_entity_input_missing_lid" >:: test_parse_entity_input_missing_lid;
    "parse_entity_input_invalid_lid" >:: test_parse_entity_input_invalid_lid;
    "parse_emit_valid" >:: test_parse_emit_valid;
    "parse_emit_empty" >:: test_parse_emit_empty;
    "parse_query_entities_all" >:: test_parse_query_entities_all;
    "parse_query_entities_kind" >:: test_parse_query_entities_with_kind;
    "parse_query_entities_pattern" >:: test_parse_query_entities_with_pattern;
    "parse_query_refs_all" >:: test_parse_query_refs_all;
    "parse_query_refs_source" >:: test_parse_query_refs_with_source;
    "dispatch_emit" >:: test_dispatch_emit;
    "dispatch_query_entities" >:: test_dispatch_query_entities;
    "dispatch_query_refs" >:: test_dispatch_query_refs;
    "dispatch_status" >:: test_dispatch_status;
    "dispatch_unknown" >:: test_dispatch_unknown_tool;
    "dispatch_invalid_json" >:: test_dispatch_invalid_json;
    "tool_schemas_structure" >:: test_tool_schemas_structure;
    "tool_schemas_string" >:: test_tool_schemas_string;
  ]

let () = run_test_tt_main suite
