(** Tests for Log module *)

open OUnit2

let temp_dir = Filename.get_temp_dir_name ()

let make_temp_path prefix =
  Filename.concat temp_dir (prefix ^ "_" ^ string_of_int (Random.int 100000))

let read_file path =
  let ic = open_in path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let cleanup paths =
  List.iter (fun p -> try Sys.remove p with _ -> ()) paths


(* ── log_path_of_db_path ── *)

let test_log_path_of_db_path_simple _ =
  let result = Log.log_path_of_db_path "context.db" in
  assert_equal "context.log" result

let test_log_path_of_db_path_with_dir _ =
  let result = Log.log_path_of_db_path "/var/data/memory.db" in
  assert_equal "/var/data/memory.log" result

let test_log_path_of_db_path_no_extension _ =
  let result = Log.log_path_of_db_path "mydb" in
  assert_equal "mydb.log" result


(* ── File creation and content ── *)

let test_setup_creates_log_file _ =
  let db_path = make_temp_path "test_setup" ^ ".db" in
  let log_path = Log.log_path_of_db_path db_path in
  let config = Log.{ db_path; level = Some Logs.Info } in
  let returned_path = Log.setup ~config () in
  assert_equal log_path returned_path;
  assert_bool "log file exists" (Sys.file_exists log_path);
  cleanup [log_path]

let test_info_writes_to_file _ =
  let db_path = make_temp_path "test_info" ^ ".db" in
  let log_path = Log.log_path_of_db_path db_path in
  let config = Log.{ db_path; level = Some Logs.Info } in
  ignore (Log.setup ~config ());
  Log.info (fun m -> m "test message 123");
  (* Force flush by reading *)
  let content = read_file log_path in
  assert_bool "contains INFO" (String.length content > 0);
  assert_bool "contains message"
    (try let _ = Str.search_forward (Str.regexp "test message 123") content 0 in true
     with Not_found -> false);
  cleanup [log_path]

let test_debug_respects_level _ =
  let db_path = make_temp_path "test_level" ^ ".db" in
  let log_path = Log.log_path_of_db_path db_path in
  (* Set level to Info - Debug should be filtered *)
  let config = Log.{ db_path; level = Some Logs.Info } in
  ignore (Log.setup ~config ());
  Log.debug (fun m -> m "debug_should_not_appear");
  Log.info (fun m -> m "info_should_appear");
  let content = read_file log_path in
  assert_bool "no debug message"
    (not (try let _ = Str.search_forward (Str.regexp "debug_should_not_appear") content 0 in true
          with Not_found -> false));
  assert_bool "has info message"
    (try let _ = Str.search_forward (Str.regexp "info_should_appear") content 0 in true
     with Not_found -> false);
  cleanup [log_path]

let test_verbose_includes_debug _ =
  let db_path = make_temp_path "test_verbose" ^ ".db" in
  let log_path = Log.log_path_of_db_path db_path in
  (* Set level to Debug *)
  let config = Log.{ db_path; level = Some Logs.Debug } in
  ignore (Log.setup ~config ());
  Log.debug (fun m -> m "debug_visible_now");
  let content = read_file log_path in
  assert_bool "has debug message"
    (try let _ = Str.search_forward (Str.regexp "debug_visible_now") content 0 in true
     with Not_found -> false);
  cleanup [log_path]


(* ── Format ── *)

let test_log_format_has_timestamp _ =
  let db_path = make_temp_path "test_format" ^ ".db" in
  let log_path = Log.log_path_of_db_path db_path in
  let config = Log.{ db_path; level = Some Logs.Info } in
  ignore (Log.setup ~config ());
  Log.info (fun m -> m "format test");
  let content = read_file log_path in
  (* Should match: 2026-03-30 15:42:02 [INFO ] ... *)
  let timestamp_regex = Str.regexp "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]" in
  assert_bool "has timestamp"
    (try let _ = Str.search_forward timestamp_regex content 0 in true
     with Not_found -> false);
  cleanup [log_path]

let test_log_format_has_level _ =
  let db_path = make_temp_path "test_level_fmt" ^ ".db" in
  let log_path = Log.log_path_of_db_path db_path in
  let config = Log.{ db_path; level = Some Logs.Warning } in
  ignore (Log.setup ~config ());
  Log.warn (fun m -> m "warning test");
  let content = read_file log_path in
  assert_bool "has WARN level"
    (try let _ = Str.search_forward (Str.regexp {|\[WARN|}) content 0 in true
     with Not_found -> false);
  cleanup [log_path]


(* ── Rotation ── *)

let test_rotate_if_needed_small_file _ =
  let path = make_temp_path "test_rotate" ^ ".log" in
  (* Create small file *)
  let oc = open_out path in
  output_string oc "small content";
  close_out oc;
  (* Should not rotate *)
  Log.rotate_if_needed path;
  assert_bool "file still exists" (Sys.file_exists path);
  assert_bool "no backup" (not (Sys.file_exists (path ^ ".old")));
  cleanup [path]


(* ── Suite ── *)

let suite =
  "log" >::: [
    "log_path_simple" >:: test_log_path_of_db_path_simple;
    "log_path_with_dir" >:: test_log_path_of_db_path_with_dir;
    "log_path_no_ext" >:: test_log_path_of_db_path_no_extension;
    "setup_creates_file" >:: test_setup_creates_log_file;
    "info_writes" >:: test_info_writes_to_file;
    "debug_filtered" >:: test_debug_respects_level;
    "verbose_debug" >:: test_verbose_includes_debug;
    "format_timestamp" >:: test_log_format_has_timestamp;
    "format_level" >:: test_log_format_has_level;
    "rotate_small" >:: test_rotate_if_needed_small_file;
  ]

let () = run_test_tt_main suite
