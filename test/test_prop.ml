(** Property-based tests using QCheck *)

open QCheck

(* ── Generators ── *)

let gen_alphanum =
  Gen.oneof
    [ Gen.char_range 'a' 'z'; Gen.char_range 'A' 'Z'; Gen.char_range '0' '9' ]

let gen_kind = Gen.oneof_list Lid.all_kinds

let gen_path =
  let segment = Gen.string_size ~gen:gen_alphanum (Gen.int_range 1 10) in
  Gen.map (String.concat "/") (Gen.list_size (Gen.int_range 1 4) segment)

let gen_lid = Gen.map2 (fun k p -> Lid.make k ~path:p) gen_kind gen_path

let gen_rel = Gen.oneof_list Ref.all_rels

let rec gen_value depth =
  if depth <= 0 then
    gen_leaf_value
  else
    Gen.oneof
      [
        gen_leaf_value;
        Gen.map
          (fun vs -> Entity.List vs)
          (Gen.list_size (Gen.int_range 0 3) (gen_value (depth - 1)));
      ]

and gen_leaf_value =
  Gen.oneof
    [
      Gen.map
        (fun s -> Entity.String s)
        (Gen.string_size ~gen:Gen.printable (Gen.int_range 0 20));
      Gen.map (fun i -> Entity.Int i) Gen.int;
      Gen.map (fun f -> Entity.Float f) (Gen.float_range (-1e6) 1e6);
      Gen.map (fun b -> Entity.Bool b) Gen.bool;
      Gen.return Entity.Null;
    ]

let gen_key = Gen.string_size ~gen:gen_alphanum (Gen.int_range 1 10)

let gen_data =
  Gen.list_size (Gen.int_range 0 5) (Gen.pair gen_key (gen_value 2))

(* ── Arbitrary instances ── *)

let arb_lid = make ~print:Lid.to_string gen_lid
let arb_kind = make ~print:Lid.prefix_of_kind gen_kind
let arb_rel = make ~print:Ref.rel_to_string gen_rel

let arb_printable_string =
  make ~print:(Printf.sprintf "%S")
    (Gen.string_size ~gen:Gen.printable (Gen.int_range 0 50))

(* ── Properties ── *)

let prop_lid_roundtrip =
  Test.make ~name:"Lid roundtrip: of_string . to_string = id" ~count:500 arb_lid
    (fun lid ->
      match Lid.of_string (Lid.to_string lid) with
      | Ok lid' -> Lid.to_string lid = Lid.to_string lid'
      | Error _ -> false)

let prop_lid_format =
  Test.make ~name:"Lid to_string contains colon" ~count:500 arb_lid (fun lid ->
      String.contains (Lid.to_string lid) ':')

let prop_lid_kind_preserved =
  Test.make ~name:"Lid kind preserved through roundtrip" ~count:500 arb_lid
    (fun lid ->
      match Lid.of_string (Lid.to_string lid) with
      | Ok lid' -> Lid.kind lid = Lid.kind lid'
      | Error _ -> false)

let prop_lid_path_preserved =
  Test.make ~name:"Lid path preserved through roundtrip" ~count:500 arb_lid
    (fun lid ->
      match Lid.of_string (Lid.to_string lid) with
      | Ok lid' -> Lid.path lid = Lid.path lid'
      | Error _ -> false)

let prop_rel_roundtrip =
  Test.make ~name:"Ref.rel roundtrip" ~count:100 arb_rel (fun rel ->
      Ref.rel_of_string (Ref.rel_to_string rel) = Some rel)

let prop_data_json_roundtrip =
  Test.make ~name:"Entity.data JSON roundtrip" ~count:500 (make gen_data)
    (fun data ->
      let encoded = Repo.encode_data data in
      let decoded = Repo.decode_data encoded in
      Repo.encode_data decoded = encoded)

let prop_string_value_roundtrip =
  Test.make ~name:"Entity.String roundtrip" ~count:500 arb_printable_string
    (fun s ->
      let data = [ ("key", Entity.String s) ] in
      let decoded = Repo.decode_data (Repo.encode_data data) in
      match List.assoc_opt "key" decoded with
      | Some (Entity.String s') -> s = s'
      | _ -> false)

let prop_int_value_roundtrip =
  Test.make ~name:"Entity.Int roundtrip" ~count:500 int (fun i ->
      let data = [ ("key", Entity.Int i) ] in
      let decoded = Repo.decode_data (Repo.encode_data data) in
      match List.assoc_opt "key" decoded with
      | Some (Entity.Int i') -> i = i'
      | _ -> false)

let prop_bool_value_roundtrip =
  Test.make ~name:"Entity.Bool roundtrip" ~count:100 bool (fun b ->
      let data = [ ("key", Entity.Bool b) ] in
      let decoded = Repo.decode_data (Repo.encode_data data) in
      match List.assoc_opt "key" decoded with
      | Some (Entity.Bool b') -> b = b'
      | _ -> false)

let prop_all_kinds_have_prefix =
  Test.make ~name:"All kinds have non-empty prefix" ~count:100 arb_kind
    (fun k -> String.length (Lid.prefix_of_kind k) > 0)

let prop_different_kinds_different_strings =
  Test.make ~name:"Different kinds produce different lid strings" ~count:500
    (pair arb_kind arb_kind) (fun (k1, k2) ->
      if k1 = k2 then
        true
      else
        let lid1 = Lid.make k1 ~path:"same" in
        let lid2 = Lid.make k2 ~path:"same" in
        Lid.to_string lid1 <> Lid.to_string lid2)

(* ── Test runner ── *)

let () =
  let suite =
    List.map QCheck_ounit.to_ounit2_test
      [
        prop_lid_roundtrip;
        prop_lid_format;
        prop_lid_kind_preserved;
        prop_lid_path_preserved;
        prop_rel_roundtrip;
        prop_data_json_roundtrip;
        prop_string_value_roundtrip;
        prop_int_value_roundtrip;
        prop_bool_value_roundtrip;
        prop_all_kinds_have_prefix;
        prop_different_kinds_different_strings;
      ]
  in
  OUnit2.run_test_tt_main (OUnit2.test_list suite)
