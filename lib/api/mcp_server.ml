(** MCP Server — JSON-RPC 2.0 stdio transport for Model Context Protocol.

    Reads newline-delimited JSON from stdin, dispatches to Tools,
    writes JSON responses to stdout. All logging goes to the log file,
    never to stdout (stdout is the protocol channel). *)

open Yojson.Safe

(* {1 JSON-RPC 2.0 helpers} *)

let jsonrpc_response ~id result =
  `Assoc [
    ("jsonrpc", `String "2.0");
    ("id", id);
    ("result", result);
  ]

let jsonrpc_error ~id ~code ~message =
  `Assoc [
    ("jsonrpc", `String "2.0");
    ("id", id);
    ("error", `Assoc [
      ("code", `Int code);
      ("message", `String message);
    ]);
  ]

(* {1 MCP protocol handlers} *)

(** Convert internal tool_schemas to MCP tools/list format *)
let mcp_tools_list () =
  let schemas = Tools.tool_schemas () in
  match schemas with
  | `Assoc fields ->
    (match List.assoc_opt "tools" fields with
     | Some (`List tools) ->
       List.map (fun tool ->
         match tool with
         | `Assoc tfields ->
           let name = List.assoc_opt "name" tfields
                      |> Option.value ~default:(`String "") in
           let description = List.assoc_opt "description" tfields
                             |> Option.value ~default:(`String "") in
           let input_schema = match List.assoc_opt "parameters" tfields with
             | Some params -> params
             | None -> `Assoc [("type", `String "object")]
           in
           `Assoc [
             ("name", name);
             ("description", description);
             ("inputSchema", input_schema);
           ]
         | other -> other
       ) tools
     | _ -> [])
  | _ -> []

(** Handle a single JSON-RPC request. Returns None for notifications. *)
let handle_request db (msg : t) : t option =
  let fields = match msg with `Assoc f -> f | _ -> [] in
  let id = List.assoc_opt "id" fields |> Option.value ~default:`Null in
  let method_name = match List.assoc_opt "method" fields with
    | Some (`String s) -> s
    | _ -> ""
  in
  let params = match List.assoc_opt "params" fields with
    | Some p -> p
    | None -> `Assoc []
  in
  match method_name with
  | "initialize" ->
    Some (jsonrpc_response ~id (`Assoc [
      ("protocolVersion", `String "2024-11-05");
      ("capabilities", `Assoc [
        ("tools", `Assoc []);
      ]);
      ("serverInfo", `Assoc [
        ("name", `String "aimemory");
        ("version", `String "0.1.1");
      ]);
    ]))

  | "notifications/initialized" ->
    None

  | "tools/list" ->
    Some (jsonrpc_response ~id (`Assoc [
      ("tools", `List (mcp_tools_list ()));
    ]))

  | "tools/call" ->
    let pfields = match params with `Assoc f -> f | _ -> [] in
    let tool_name = match List.assoc_opt "name" pfields with
      | Some (`String s) -> s
      | _ -> ""
    in
    let tool_args = match List.assoc_opt "arguments" pfields with
      | Some args -> Yojson.Safe.to_string args
      | None -> "{}"
    in
    let result = Tools.dispatch db ~tool:tool_name ~args:tool_args in
    Some (jsonrpc_response ~id (`Assoc [
      ("content", `List [
        `Assoc [
          ("type", `String "text");
          ("text", `String result);
        ];
      ]);
    ]))

  | "ping" ->
    Some (jsonrpc_response ~id (`Assoc []))

  | _ ->
    Some (jsonrpc_error ~id ~code:(-32601)
            ~message:("Method not found: " ^ method_name))

(** Send a JSON-RPC response to stdout *)
let send response =
  let out = Yojson.Safe.to_string response in
  Log.debug (fun m -> m "MCP send: %s" out);
  print_string out;
  print_char '\n';
  flush stdout

(** Main loop: read JSON-RPC from stdin, dispatch, respond on stdout *)
let run db =
  Log.info (fun m -> m "MCP server starting (stdio)");
  try
    while true do
      let line = input_line stdin in
      if String.trim line <> "" then begin
        Log.debug (fun m -> m "MCP recv: %s" line);
        match Yojson.Safe.from_string line with
        | msg ->
          (match handle_request db msg with
           | Some response -> send response
           | None -> ())
        | exception Yojson.Json_error e ->
          send (jsonrpc_error ~id:`Null ~code:(-32700)
                  ~message:("Parse error: " ^ e))
      end
    done
  with End_of_file ->
    Log.info (fun m -> m "MCP server: stdin closed, shutting down")
