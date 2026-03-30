(* CLI for context memory — allows AI to use Tools.dispatch via command line *)

let db_path = ref "context.db"

let usage = {|
AI Memory CLI

Usage:
  aimemory call <tool> <json_args>    Call a tool with JSON arguments
  aimemory schemas                     Print tool schemas for system prompt
  aimemory status                      Show database status
  aimemory reset                       Delete database and start fresh

Tools: emit, query_entities, query_refs, status

Examples:
  aimemory call emit '{"entities":[{"lid":"fn:auth/login","data":{"async":true}}]}'
  aimemory call query_entities '{"kind":"fn"}'
  aimemory call query_refs '{"source":"fn:auth/login"}'
  aimemory status
|}

let with_db f =
  match Repo.open_db !db_path with
  | Ok db ->
    let result = f db in
    Repo.close db;
    result
  | Error e ->
    Printf.eprintf "Database error: %s\n" (Repo.pp_error e);
    exit 1

let cmd_call tool args =
  with_db (fun db ->
    let result = Tools.dispatch db ~tool ~args in
    print_endline result
  )

let cmd_schemas () =
  print_endline (Tools.tool_schemas_string ())

let cmd_status () =
  with_db (fun db ->
    let result = Tools.dispatch db ~tool:"status" ~args:"{}" in
    print_endline result
  )

let cmd_reset () =
  if Sys.file_exists !db_path then begin
    Sys.remove !db_path;
    Printf.printf "Deleted %s\n" !db_path
  end else
    Printf.printf "No database at %s\n" !db_path

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  match args with
  | ["call"; tool; json_args] -> cmd_call tool json_args
  | ["schemas"] -> cmd_schemas ()
  | ["status"] -> cmd_status ()
  | ["reset"] -> cmd_reset ()
  | ["--db"; path; "call"; tool; json_args] ->
    db_path := path;
    cmd_call tool json_args
  | ["--db"; path; "status"] ->
    db_path := path;
    cmd_status ()
  | ["--db"; path; "reset"] ->
    db_path := path;
    cmd_reset ()
  | _ ->
    print_endline usage;
    exit 1
