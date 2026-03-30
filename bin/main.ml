(* CLI for context memory — allows AI to use Tools.dispatch via command line *)

let db_path = ref "context.db"
let log_level = ref (Some Logs.Info)

let usage = {|
AI Memory CLI

Usage:
  aimemory call <tool> <json_args>    Call a tool with JSON arguments
  aimemory schemas                     Print tool schemas for system prompt
  aimemory status                      Show database status
  aimemory reset                       Delete database and start fresh

Options:
  --db <path>       Use custom database path (default: context.db)
  --verbose         Enable debug logging
  --quiet           Disable logging (errors still shown in stderr)

Tools: emit, query_entities, query_refs, status

Examples:
  aimemory call emit '{"entities":[{"lid":"fn:auth/login","data":{"async":true}}]}'
  aimemory call query_entities '{"kind":"fn"}'
  aimemory call query_refs '{"source":"fn:auth/login"}'
  aimemory status

Logs are written to <db_name>.log (e.g., context.log for context.db)
|}

let setup_logging () =
  let config = Log.{
    db_path = !db_path;
    level = !log_level;
  } in
  ignore (Log.setup ~config ())

let with_db f =
  match Repo.open_db !db_path with
  | Ok db ->
    let result = f db in
    Repo.close db;
    result
  | Error e ->
    Log.err (fun m -> m "Database error: %s" (Repo.pp_error e));
    Printf.eprintf "Database error: %s\n" (Repo.pp_error e);
    exit 1

let cmd_call tool args =
  Log.info (fun m -> m "call %s" tool);
  with_db (fun db ->
    let result = Tools.dispatch db ~tool ~args in
    print_endline result
  )

let cmd_schemas () =
  print_endline (Tools.tool_schemas_string ())

let cmd_status () =
  Log.info (fun m -> m "status");
  with_db (fun db ->
    let result = Tools.dispatch db ~tool:"status" ~args:"{}" in
    print_endline result
  )

let cmd_reset () =
  Log.info (fun m -> m "reset");
  if Sys.file_exists !db_path then begin
    Sys.remove !db_path;
    Log.info (fun m -> m "deleted %s" !db_path);
    Printf.printf "Deleted %s\n" !db_path
  end else
    Printf.printf "No database at %s\n" !db_path

(* Parse options from args, return remaining args *)
let rec parse_options = function
  | "--db" :: path :: rest ->
      db_path := path;
      parse_options rest
  | "--verbose" :: rest ->
      log_level := Some Logs.Debug;
      parse_options rest
  | "--quiet" :: rest ->
      log_level := None;
      parse_options rest
  | args -> args

let run_command = function
  | ["call"; tool; json_args] -> cmd_call tool json_args
  | ["schemas"] -> cmd_schemas ()
  | ["status"] -> cmd_status ()
  | ["reset"] -> cmd_reset ()
  | _ ->
      print_endline usage;
      exit 1

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  let command_args = parse_options args in
  setup_logging ();
  run_command command_args
