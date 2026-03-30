(** Тесты доменной логики: Lid, Entity, Ref, Protocol Запуск: ocamlfind ocamlopt
    -package ounit2 -linkpkg test_domain.ml -o test_domain && ./test_domain Или
    через dune — см. dune файл ниже. *)

open OUnit2

(* ── Stub: Lid ── *)
module Lid = struct
  type kind =
    | Comp
    | View
    | Layout
    | Store
    | Service
    | Composable
    | Intercept
    | Validator
    | Util
    | Plugin
    | Provider
    | Route
    | Locale
    | Const
    | Style
    | Unit
    | E2e
    | Asset
    | Api
    | Dep
    | Fn
    | State
    | Computed
    | Action
    | Prop
    | Emit
    | Hook
    | Typ
    | Provide

  type parse_error =
    | Empty
    | Missing_colon
    | Unknown_kind of string
    | Empty_path

  type t = { kind : kind; path : string }

  let prefix_of_kind = function
    | Comp -> "comp"
    | View -> "view"
    | Layout -> "layout"
    | Store -> "store"
    | Service -> "service"
    | Composable -> "composable"
    | Intercept -> "intercept"
    | Validator -> "validator"
    | Util -> "util"
    | Plugin -> "plugin"
    | Provider -> "provider"
    | Route -> "route"
    | Locale -> "locale"
    | Const -> "const"
    | Style -> "style"
    | Unit -> "unit"
    | E2e -> "e2e"
    | Asset -> "asset"
    | Api -> "api"
    | Dep -> "dep"
    | Fn -> "fn"
    | State -> "state"
    | Computed -> "computed"
    | Action -> "action"
    | Prop -> "prop"
    | Emit -> "emit"
    | Hook -> "hook"
    | Typ -> "type"
    | Provide -> "provide"

  let kind_of_prefix = function
    | "comp" -> Some Comp
    | "view" -> Some View
    | "layout" -> Some Layout
    | "store" -> Some Store
    | "service" -> Some Service
    | "composable" -> Some Composable
    | "intercept" -> Some Intercept
    | "validator" -> Some Validator
    | "util" -> Some Util
    | "plugin" -> Some Plugin
    | "provider" -> Some Provider
    | "route" -> Some Route
    | "locale" -> Some Locale
    | "const" -> Some Const
    | "style" -> Some Style
    | "unit" -> Some Unit
    | "e2e" -> Some E2e
    | "asset" -> Some Asset
    | "api" -> Some Api
    | "dep" -> Some Dep
    | "fn" -> Some Fn
    | "state" -> Some State
    | "computed" -> Some Computed
    | "action" -> Some Action
    | "prop" -> Some Prop
    | "emit" -> Some Emit
    | "hook" -> Some Hook
    | "type" -> Some Typ
    | "provide" -> Some Provide
    | _ -> None

  let of_string s =
    if String.length s = 0 then Error Empty
    else
      match String.index_opt s ':' with
      | None -> Error Missing_colon
      | Some i -> (
          let prefix = String.sub s 0 i in
          let path = String.sub s (i + 1) (String.length s - i - 1) in
          if String.length path = 0 then Error Empty_path
          else
            match kind_of_prefix prefix with
            | None -> Error (Unknown_kind prefix)
            | Some kind -> Ok { kind; path })

  let make kind ~path = { kind; path }
  let to_string { kind; path } = prefix_of_kind kind ^ ":" ^ path
  let kind t = t.kind
  let path t = t.path

  let all_kinds =
    [
      Comp;
      View;
      Layout;
      Store;
      Service;
      Composable;
      Intercept;
      Validator;
      Util;
      Plugin;
      Provider;
      Route;
      Locale;
      Const;
      Style;
      Unit;
      E2e;
      Asset;
      Api;
      Dep;
      Fn;
      State;
      Computed;
      Action;
      Prop;
      Emit;
      Hook;
      Typ;
      Provide;
    ]

  module T = struct
    type nonrec t = t

    let compare a b = String.compare (to_string a) (to_string b)
  end

  module Map = Map.Make (T)
  module Set = Set.Make (T)
end

(* ── Stub: Entity ── *)
module Entity = struct
  type value =
    | String of string
    | Int of int
    | Float of float
    | Bool of bool
    | List of value list
    | Null

  type data = (string * value) list
  type raw = { lid : Lid.t; data : data }

  type processed = {
    id : int;
    lid : Lid.t;
    data : data;
    created : float;
    updated : float;
  }
end

(* ── Stub: Ref ── *)
module Ref_ = struct
  type rel =
    | Belongs_to
    | Calls
    | Depends_on
    | Contains
    | Implements
    | References

  type pending = { source : Lid.t; target : Lid.t; rel : rel }

  type resolved = {
    source : Lid.t;
    target : Lid.t;
    rel : rel;
    source_id : int;
    target_id : int;
  }

  type resolution =
    | Resolved of resolved
    | Source_missing of pending
    | Target_missing of pending
    | Both_missing of pending

  (** Попытка resolve: ищем source и target в таблице id_of_lid *)
  let resolve (id_of_lid : Lid.t -> int option) (p : pending) : resolution =
    match (id_of_lid p.source, id_of_lid p.target) with
    | Some source_id, Some target_id ->
        Resolved
          {
            source = p.source;
            target = p.target;
            rel = p.rel;
            source_id;
            target_id;
          }
    | None, None -> Both_missing p
    | None, _ -> Source_missing p
    | _, None -> Target_missing p
end

(* ── Stub: Protocol ── *)
module Protocol = struct
  type entity_input = { lid : Lid.t; data : Entity.data; refs : ref_input list }
  and ref_input = { target : Lid.t; rel : Ref_.rel }

  type emit_payload = { entities : entity_input list }
  type entity_query = { kind : Lid.kind option; pattern : string option }

  type ref_query = {
    source : Lid.t option;
    target : Lid.t option;
    rel_type : Ref_.rel option;
  }

  type command =
    | Emit of emit_payload
    | Query_entities of entity_query
    | Query_refs of ref_query

  type emit_result = {
    upserted : Lid.t list;
    refs_resolved : Ref_.resolved list;
    refs_pending : Ref_.pending list;
  }

  type protocol_error =
    | Invalid_lid of string * Lid.parse_error
    | Storage_error of string
    | Unknown_command of string

  type response =
    | Emit_result of emit_result
    | Entities of Entity.processed list
    | Refs of Ref_.resolved list
    | Error of protocol_error
end

(* ════════════════════════════════════════════ *)
(*                   ТЕСТЫ                      *)
(* ════════════════════════════════════════════ *)

(* ── 1. Lid.of_string — валидные случаи ── *)
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
  (* Особый случай: kind = Typ, но префикс = "type" *)
  match Lid.of_string "type:UserDto" with
  | Ok lid ->
      assert_equal Lid.Typ (Lid.kind lid);
      assert_equal "UserDto" (Lid.path lid)
  | Error _ -> assert_failure "Expected Ok for 'type:UserDto'"

let test_lid_parse_path_with_slashes _ =
  match Lid.of_string "fn:auth/login/validatePassword" with
  | Ok lid -> assert_equal "auth/login/validatePassword" (Lid.path lid)
  | Error _ -> assert_failure "Expected Ok for deep path"

(* ── 2. Lid.of_string — ошибки ── *)
let test_lid_parse_empty _ = assert_equal (Error Lid.Empty) (Lid.of_string "")

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
  (* Все kind → prefix → of_string должны вернуть тот же kind *)
  List.iter
    (fun k ->
      let s = Lid.prefix_of_kind k ^ ":somepath" in
      match Lid.of_string s with
      | Ok lid -> assert_equal k (Lid.kind lid) ~msg:s
      | Error _ -> assert_failure ("Roundtrip failed for: " ^ s))
    Lid.all_kinds

(* ── 4. Lid равенство и сравнение ── *)
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

(* ── 6. Entity.value — структура данных ── *)
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

let test_entity_stored_has_id _ =
  let lid = Lid.make Lid.Store ~path:"cart" in
  let stored =
    Entity.
      { id = 7; lid; data = []; created = 1_000_000.0; updated = 1_000_001.0 }
  in
  assert_equal 7 stored.id;
  assert_bool "created <= updated" (stored.created <= stored.updated)

(* ── 7. Ref_.resolve ── *)

(** Простой lookup по to_string *)
let make_lookup tbl lid =
  let key = Lid.to_string lid in
  List.assoc_opt key tbl

let test_ref_resolve_both_exist _ =
  let src = Lid.make Lid.Fn ~path:"doA" in
  let tgt = Lid.make Lid.Fn ~path:"doB" in
  let tbl = [ (Lid.to_string src, 10); (Lid.to_string tgt, 20) ] in
  let pending = Ref_.{ source = src; target = tgt; rel = Ref_.Calls } in
  match Ref_.resolve (make_lookup tbl) pending with
  | Ref_.Resolved r ->
      assert_equal 10 r.source_id;
      assert_equal 20 r.target_id;
      assert_equal Ref_.Calls r.rel
  | _ -> assert_failure "Expected Resolved"

let test_ref_resolve_target_missing _ =
  let src = Lid.make Lid.Fn ~path:"doA" in
  let tgt = Lid.make Lid.Fn ~path:"ghost" in
  let tbl = [ (Lid.to_string src, 10) ] in
  let pending = Ref_.{ source = src; target = tgt; rel = Ref_.Calls } in
  match Ref_.resolve (make_lookup tbl) pending with
  | Ref_.Target_missing p -> assert_equal pending p
  | _ -> assert_failure "Expected Target_missing"

let test_ref_resolve_source_missing _ =
  let src = Lid.make Lid.Fn ~path:"ghost" in
  let tgt = Lid.make Lid.Fn ~path:"doB" in
  let tbl = [ (Lid.to_string tgt, 20) ] in
  let pending = Ref_.{ source = src; target = tgt; rel = Ref_.Calls } in
  match Ref_.resolve (make_lookup tbl) pending with
  | Ref_.Source_missing _ -> ()
  | _ -> assert_failure "Expected Source_missing"

let test_ref_resolve_both_missing _ =
  let src = Lid.make Lid.Fn ~path:"ghostA" in
  let tgt = Lid.make Lid.Fn ~path:"ghostB" in
  let pending = Ref_.{ source = src; target = tgt; rel = Ref_.Belongs_to } in
  match Ref_.resolve (make_lookup []) pending with
  | Ref_.Both_missing _ -> ()
  | _ -> assert_failure "Expected Both_missing"

let test_ref_all_rel_types _ =
  (* Убеждаемся что все rel конструкторы матчатся корректно *)
  let rels =
    Ref_.[ Belongs_to; Calls; Depends_on; Contains; Implements; References ]
  in
  let src = Lid.make Lid.Fn ~path:"s" in
  let tgt = Lid.make Lid.Fn ~path:"t" in
  List.iter
    (fun rel ->
      let p = Ref_.{ source = src; target = tgt; rel } in
      let tbl = [ (Lid.to_string src, 1); (Lid.to_string tgt, 2) ] in
      match Ref_.resolve (make_lookup tbl) p with
      | Ref_.Resolved r -> assert_equal rel r.rel
      | _ -> assert_failure "Expected Resolved")
    rels

(* ── 8. Protocol — конструирование команд и ответов ── *)
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
  let ref_in = Protocol.{ target = tgt; rel = Ref_.Calls } in
  let input = Protocol.{ lid = src; data = []; refs = [ ref_in ] } in
  let cmd = Protocol.Emit { Protocol.entities = [ input ] } in
  match cmd with
  | Protocol.Emit p ->
      let refs = (List.hd p.Protocol.entities).Protocol.refs in
      assert_equal 1 (List.length refs);
      assert_equal Ref_.Calls (List.hd refs).Protocol.rel
  | _ -> assert_failure "Expected Emit"

let test_protocol_query_entities_with_kind _ =
  let q = Protocol.{ kind = Some Lid.Store; pattern = None } in
  let cmd = Protocol.Query_entities q in
  match cmd with
  | Protocol.Query_entities q -> assert_equal (Some Lid.Store) q.Protocol.kind
  | _ -> assert_failure "Expected Query_entities"

let test_protocol_query_refs _ =
  let src = Lid.make Lid.Fn ~path:"login" in
  let q =
    Protocol.{ source = Some src; target = None; rel_type = Some Ref_.Calls }
  in
  let cmd = Protocol.Query_refs q in
  match cmd with
  | Protocol.Query_refs q ->
      assert_equal (Some src) q.Protocol.source;
      assert_equal (Some Ref_.Calls) q.Protocol.rel_type
  | _ -> assert_failure "Expected Query_refs"

let test_protocol_emit_result _ =
  let lid = Lid.make Lid.Comp ~path:"ui/Button" in
  let result =
    Protocol.{ upserted = [ lid ]; refs_resolved = []; refs_pending = [] }
  in
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

(* ── 9. Инвариант: to_string ∘ of_string = id ── *)
let test_lid_of_string_to_string_identity _ =
  let cases =
    [
      "comp:ui/Button";
      "store:auth";
      "fn:utils/formatDate";
      "type:UserDto";
      "provide:theme";
      "e2e:login-flow";
    ]
  in
  List.iter
    (fun s ->
      match Lid.of_string s with
      | Ok lid ->
          assert_equal s (Lid.to_string lid) ~msg:("Identity failed: " ^ s)
      | Error _ -> assert_failure ("Parse failed: " ^ s))
    cases

(* ════════════════════════════════════════════ *)
(*               СБОРКА SUITE                   *)
(* ════════════════════════════════════════════ *)

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
         "entity_stored_has_id" >:: test_entity_stored_has_id;
         (* Ref_.resolve *)
         "ref_resolve_both_exist" >:: test_ref_resolve_both_exist;
         "ref_resolve_target_missing" >:: test_ref_resolve_target_missing;
         "ref_resolve_source_missing" >:: test_ref_resolve_source_missing;
         "ref_resolve_both_missing" >:: test_ref_resolve_both_missing;
         "ref_all_rel_types" >:: test_ref_all_rel_types;
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
