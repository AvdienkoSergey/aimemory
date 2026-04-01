(** Tools — MCP-like tool interface for AI interaction.

    This module is the boundary between JSON (AI world) and typed domain (OCaml
    world). It provides:

    - [dispatch]: tool_name × JSON args => JSON result
    - [tool_schemas]: exportable tool definitions for system prompts
    - JSON ↔ domain type conversion (private)

    All parsing errors become structured JSON error responses — the AI never
    sees OCaml exceptions. *)

open Yojson.Safe

(** {1 JSON ↔ Domain converters} *)

let value_to_json = Repo.value_to_json
let json_to_value = Repo.json_to_value

(** Convert JSON object => [Entity.data] *)
let json_to_data (j : t) : Entity.data =
  match j with
  | `Assoc pairs -> List.map (fun (k, v) -> (k, json_to_value v)) pairs
  | _ -> []

(** Convert [Entity.data] => JSON object *)
let data_to_json (d : Entity.data) : t =
  `Assoc (List.map (fun (k, v) -> (k, value_to_json v)) d)

(** Convert [Ref.rel] ↔ string *)
let rel_of_json (j : t) : Ref.rel option =
  match j with `String s -> Ref.rel_of_string s | _ -> None

let rel_to_json (r : Ref.rel) : t = `String (Ref.rel_to_string r)

(** Convert [Lid.kind] ↔ string *)
let kind_of_json (j : t) : Lid.kind option =
  match j with
  | `String s -> (
      (* Reuse Lid.of_string with a dummy path to extract kind *)
      match Lid.of_string (s ^ ":_") with
      | Ok lid -> Some (Lid.kind lid)
      | Error _ -> None)
  | _ -> None

(** {1 Response serialization} *)

let entity_to_json (e : Entity.processed) : t =
  `Assoc
    [
      ("id", `Int e.id);
      ("lid", `String (Lid.to_string e.lid));
      ("kind", `String (Lid.prefix_of_kind (Lid.kind e.lid)));
      ("path", `String (Lid.path e.lid));
      ("data", data_to_json e.data);
      ("created", `Float e.created);
      ("updated", `Float e.updated);
    ]

let resolved_ref_to_json (r : Ref.resolved) : t =
  `Assoc
    [
      ("source", `String (Lid.to_string r.source));
      ("target", `String (Lid.to_string r.target));
      ("rel", rel_to_json r.rel);
      ("source_id", `Int r.source_id);
      ("target_id", `Int r.target_id);
    ]

let pending_ref_to_json (r : Ref.pending) : t =
  `Assoc
    [
      ("source", `String (Lid.to_string r.source));
      ("target", `String (Lid.to_string r.target));
      ("rel", rel_to_json r.rel);
      ("status", `String "pending");
    ]

let response_to_json (resp : Protocol.response) : t =
  match resp with
  | Emit_result r ->
      `Assoc
        [
          ("status", `String "ok");
          ("command", `String "emit");
          ( "upserted",
            `List (List.map (fun lid -> `String (Lid.to_string lid)) r.upserted)
          );
          ( "refs_resolved",
            `List (List.map resolved_ref_to_json r.refs_resolved) );
          ("refs_pending", `List (List.map pending_ref_to_json r.refs_pending));
        ]
  | Entities r ->
      `Assoc
        [
          ("status", `String "ok");
          ("command", `String "query_entities");
          ("entities", `List (List.map entity_to_json r.items));
          ("count", `Int (List.length r.items));
          ("total", `Int r.page.total);
          ("has_more", `Bool r.page.has_more);
        ]
  | Refs r ->
      `Assoc
        [
          ("status", `String "ok");
          ("command", `String "query_refs");
          ("refs", `List (List.map resolved_ref_to_json r.items));
          ("count", `Int (List.length r.items));
          ("total", `Int r.page.total);
          ("has_more", `Bool r.page.has_more);
        ]
  | Error e ->
      let msg =
        match e with
        | Protocol.Invalid_lid (s, pe) ->
            Printf.sprintf "Invalid LID '%s': %s" s (Lid.pp_parse_error pe)
        | Protocol.Storage_error s -> s
        | Protocol.Unknown_command s -> "Unknown command: " ^ s
      in
      `Assoc [ ("status", `String "error"); ("message", `String msg) ]

(** {1 Request parsing} *)

(** Parse a single entity_input from JSON. Expected shape:
    {[
     { "lid": "mod:auth/login",
         "data": { "name": "login", "loc": 120 },
         "refs": [ { "target": "file:src/auth.ml", "rel": "belongs_to" } ] }
    ]} *)
let parse_entity_input (j : t) : (Protocol.entity_input, string) result =
  match j with
  | `Assoc fields -> (
      let lid_s =
        match List.assoc_opt "lid" fields with
        | Some (`String s) -> Some s
        | _ -> None
      in
      match lid_s with
      | None -> Error "entity_input: missing or invalid 'lid' field"
      | Some s -> (
          match Lid.of_string s with
          | Error e ->
              Error
                (Printf.sprintf "Invalid LID '%s': %s" s (Lid.pp_parse_error e))
          | Ok lid ->
              let data =
                match List.assoc_opt "data" fields with
                | Some d -> json_to_data d
                | None -> []
              in
              let refs =
                match List.assoc_opt "refs" fields with
                | Some (`List rs) ->
                    List.filter_map
                      (fun r ->
                        match r with
                        | `Assoc rf -> (
                            let target_s =
                              match List.assoc_opt "target" rf with
                              | Some (`String s) -> Some s
                              | _ -> None
                            in
                            let rel_s =
                              match List.assoc_opt "rel" rf with
                              | Some (`String s) -> Some s
                              | _ -> None
                            in
                            match (target_s, rel_s) with
                            | Some ts, Some rs -> (
                                match
                                  (Lid.of_string ts, Ref.rel_of_string rs)
                                with
                                | Ok target, Some rel ->
                                    Some Protocol.{ target; rel }
                                | _ -> None)
                            | _ -> None)
                        | _ -> None)
                      rs
                | _ -> []
              in
              Ok Protocol.{ lid; data; refs }))
  | _ -> Error "entity_input: expected JSON object"

(** Parse an emit command.
    Expected: { "entities": [ ... ] } *)
let parse_emit (j : t) : (Protocol.command, string) result =
  match j with
  | `Assoc fields -> (
      let entities_json =
        match List.assoc_opt "entities" fields with
        | Some (`List es) -> es
        | _ -> []
      in
      if entities_json = [] then
        Error "emit: 'entities' array is empty or missing"
      else
        let rec parse_all acc = function
          | [] -> Ok (List.rev acc)
          | ej :: rest -> (
              match parse_entity_input ej with
              | Ok ei -> parse_all (ei :: acc) rest
              | Error e -> Error e)
        in
        match parse_all [] entities_json with
        | Ok inputs -> Ok (Protocol.Emit { entities = inputs })
        | Error e -> Error e)
  | _ -> Error "emit: expected JSON object"

let parse_int_opt key fields =
  match List.assoc_opt key fields with Some (`Int n) -> Some n | _ -> None

(** Parse a query_entities command.
    Expected: { "kind": "fn", "pattern": "auth/*", "limit": 50, "offset": 0 }
    All fields optional. *)
let parse_query_entities (j : t) : (Protocol.command, string) result =
  match j with
  | `Assoc fields ->
      let kind =
        match List.assoc_opt "kind" fields with
        | Some k -> kind_of_json k
        | None -> None
      in
      let pattern =
        match List.assoc_opt "pattern" fields with
        | Some (`String s) -> Some s
        | _ -> None
      in
      let limit = parse_int_opt "limit" fields in
      let offset = parse_int_opt "offset" fields in
      Ok (Protocol.Query_entities { kind; pattern; limit; offset })
  | _ -> Ok (Protocol.Query_entities Protocol.query_all_entities)

(** Parse a query_refs command.
    Expected: { "source": "fn:...", "target": "mod:...", "rel": "calls", "limit": 50 }
    All fields optional. *)
let parse_query_refs (j : t) : (Protocol.command, string) result =
  match j with
  | `Assoc fields -> (
      let parse_lid_opt key =
        match List.assoc_opt key fields with
        | Some (`String s) -> (
            match Lid.of_string s with
            | Ok lid -> Ok (Some lid)
            | Error e ->
                Error
                  (Printf.sprintf "Invalid LID in '%s': %s" key
                     (Lid.pp_parse_error e)))
        | _ -> Ok None
      in
      match (parse_lid_opt "source", parse_lid_opt "target") with
      | Ok source, Ok target ->
          let rel_type =
            match List.assoc_opt "rel" fields with
            | Some r -> rel_of_json r
            | None -> None
          in
          let limit = parse_int_opt "limit" fields in
          let offset = parse_int_opt "offset" fields in
          Ok (Protocol.Query_refs { source; target; rel_type; limit; offset })
      | Error e, _ | _, Error e -> Error e)
  | _ -> Ok (Protocol.Query_refs Protocol.query_all_refs)

(** {1 Dispatch} *)

(** Error response as JSON string *)
let json_error msg =
  Log.warn (fun m -> m "tool error: %s" msg);
  Yojson.Safe.to_string
    (`Assoc [ ("status", `String "error"); ("message", `String msg) ])

(** Main dispatch: tool_name × JSON string => JSON string. This is the function
    your OCaml program calls when AI invokes a tool. *)
let dispatch (db : Repo.t) ~(tool : string) ~(args : string) : string =
  let parse_result =
    try
      let j = Yojson.Safe.from_string args in
      match tool with
      | "emit" -> parse_emit j
      | "query_entities" -> parse_query_entities j
      | "query_refs" -> parse_query_refs j
      | "status" -> Ok (Protocol.Query_entities Protocol.query_all_entities)
      | other -> Error (Printf.sprintf "Unknown tool: %s" other)
    with Yojson.Json_error msg -> Error ("JSON parse error: " ^ msg)
  in
  match parse_result with
  | Error msg -> json_error msg
  | Ok cmd ->
      (* Special case: status returns richer info *)
      if tool = "status" then
        match Ingest.status db with
        | Ok s ->
            Yojson.Safe.to_string
              (`Assoc
                 [
                   ("status", `String "ok");
                   ("command", `String "status");
                   ("entity_count", `Int s.stats.entity_count);
                   ("ref_resolved_count", `Int s.stats.ref_resolved_count);
                   ("ref_pending_count", `Int s.stats.ref_pending_count);
                   ( "missing_entities",
                     `List
                       (List.map
                          (fun (lid, n) ->
                            `Assoc
                              [
                                ("lid", `String (Lid.to_string lid));
                                ("blocking_refs", `Int n);
                              ])
                          s.missing.missing_lids) );
                   ("summary", `String (Ingest.pp_status s));
                 ])
        | Error e -> json_error (Repo.pp_error e)
      else
        let resp = Ingest.process db cmd in
        Yojson.Safe.to_string (response_to_json resp)

(** {1 Tool schemas for system prompts} *)

(** Generate MCP-compatible tool definitions as JSON. Inject this into the AI's
    system prompt so it knows what tools are available and how to call them. *)
let tool_schemas () : t =
  `Assoc
    [
      ("protocol", `String "context-memory/v1");
      ( "tools",
        `List
          [
            (* emit *)
            `Assoc
              [
                ("name", `String "emit");
                ( "description",
                  `String
                    "Upsert entities into context memory with optional \
                     references. Entities are identified by LID (logical ID) \
                     in format 'kind:path'. References to non-existent \
                     entities are stored as pending and auto-resolved when the \
                     target appears." );
                ( "parameters",
                  `Assoc
                    [
                      ("type", `String "object");
                      ("required", `List [ `String "entities" ]);
                      ( "properties",
                        `Assoc
                          [
                            ( "entities",
                              `Assoc
                                [
                                  ("type", `String "array");
                                  ( "description",
                                    `String "Array of entities to upsert" );
                                  ( "items",
                                    `Assoc
                                      [
                                        ("type", `String "object");
                                        ("required", `List [ `String "lid" ]);
                                        ( "properties",
                                          `Assoc
                                            [
                                              ( "lid",
                                                `Assoc
                                                  [
                                                    ("type", `String "string");
                                                    ( "description",
                                                      `String
                                                        "Logical ID in format \
                                                         'kind:path'. Jira \
                                                         kinds: issue, epic, \
                                                         sprint, board, \
                                                         version, jproject, \
                                                         juser. GitLab kinds: \
                                                         mr, pipeline, job, \
                                                         commit, branch, \
                                                         deploy, release, \
                                                         glproject, gluser, \
                                                         milestone. Examples: \
                                                         'issue:DBO-123', \
                                                         'mr:backend/456', \
                                                         'pipeline:789', \
                                                         'commit:abc123def', \
                                                         'sprint:42'" );
                                                  ] );
                                              ( "data",
                                                `Assoc
                                                  [
                                                    ("type", `String "object");
                                                    ( "description",
                                                      `String
                                                        "Arbitrary key-value \
                                                         data for this entity. \
                                                         Values can be \
                                                         strings, numbers, \
                                                         booleans, arrays, or \
                                                         null." );
                                                  ] );
                                              ( "refs",
                                                `Assoc
                                                  [
                                                    ("type", `String "array");
                                                    ( "description",
                                                      `String
                                                        "References to other \
                                                         entities" );
                                                    ( "items",
                                                      `Assoc
                                                        [
                                                          ( "type",
                                                            `String "object" );
                                                          ( "required",
                                                            `List
                                                              [
                                                                `String "target";
                                                                `String "rel";
                                                              ] );
                                                          ( "properties",
                                                            `Assoc
                                                              [
                                                                ( "target",
                                                                  `Assoc
                                                                    [
                                                                      ( "type",
                                                                        `String
                                                                          "string"
                                                                      );
                                                                      ( "description",
                                                                        `String
                                                                          "LID \
                                                                           of \
                                                                           the \
                                                                           target \
                                                                           entity"
                                                                      );
                                                                    ] );
                                                                ( "rel",
                                                                  `Assoc
                                                                    [
                                                                      ( "type",
                                                                        `String
                                                                          "string"
                                                                      );
                                                                      ( "enum",
                                                                        `List
                                                                          (List
                                                                           .map
                                                                             (fun 
                                                                               r
                                                                             ->
                                                                               `String
                                                                                (
                                                                                Ref
                                                                                .rel_to_string
                                                                                r))
                                                                             Ref
                                                                             .all_rels)
                                                                      );
                                                                      ( "description",
                                                                        `String
                                                                          "linked_to: \
                                                                           issue \
                                                                           linked \
                                                                           to \
                                                                           mr \
                                                                           via \
                                                                           DevStatus. \
                                                                           belongs_to: \
                                                                           issue \
                                                                           in \
                                                                           sprint, \
                                                                           mr \
                                                                           in \
                                                                           pipeline. \
                                                                           contains: \
                                                                           sprint \
                                                                           has \
                                                                           issues, \
                                                                           pipeline \
                                                                           has \
                                                                           jobs. \
                                                                           triggered_by: \
                                                                           pipeline \
                                                                           from \
                                                                           mr. \
                                                                           deployed_via: \
                                                                           issue \
                                                                           in \
                                                                           deployment. \
                                                                           reviewed_by: \
                                                                           mr \
                                                                           reviewer. \
                                                                           assigned_to: \
                                                                           issue/mr \
                                                                           assignee. \
                                                                           references: \
                                                                           generic \
                                                                           fallback."
                                                                      );
                                                                    ] );
                                                              ] );
                                                        ] );
                                                  ] );
                                            ] );
                                      ] );
                                ] );
                          ] );
                    ] );
              ];
            (* query_entities *)
            `Assoc
              [
                ("name", `String "query_entities");
                ( "description",
                  `String
                    "Query entities in context memory. Use to discover what \
                     LIDs already exist before emitting refs. Returns entities \
                     with their data and physical IDs." );
                ( "parameters",
                  `Assoc
                    [
                      ("type", `String "object");
                      ( "properties",
                        `Assoc
                          [
                            ( "kind",
                              `Assoc
                                [
                                  ("type", `String "string");
                                  ( "enum",
                                    `List
                                      (List.map
                                         (fun k ->
                                           `String (Lid.prefix_of_kind k))
                                         Lid.all_kinds) );
                                  ( "description",
                                    `String
                                      "Filter by entity kind. Jira: issue, \
                                       epic, sprint, board, version, jproject, \
                                       juser. GitLab: mr, pipeline, job, \
                                       commit, branch, deploy, release, \
                                       glproject, gluser, milestone." );
                                ] );
                            ( "pattern",
                              `Assoc
                                [
                                  ("type", `String "string");
                                  ( "description",
                                    `String
                                      "Glob pattern on the path portion. Use * \
                                       as wildcard. Examples: 'auth/*', \
                                       '*/login', '*'" );
                                ] );
                            ( "limit",
                              `Assoc
                                [
                                  ("type", `String "integer");
                                  ( "description",
                                    `String
                                      "Max results to return. Default 100, max \
                                       1000." );
                                ] );
                            ( "offset",
                              `Assoc
                                [
                                  ("type", `String "integer");
                                  ( "description",
                                    `String
                                      "Skip first N results for pagination." );
                                ] );
                          ] );
                    ] );
              ];
            (* query_refs *)
            `Assoc
              [
                ("name", `String "query_refs");
                ( "description",
                  `String
                    "Query resolved references between entities. Only returns \
                     refs where both source and target exist." );
                ( "parameters",
                  `Assoc
                    [
                      ("type", `String "object");
                      ( "properties",
                        `Assoc
                          [
                            ( "source",
                              `Assoc
                                [
                                  ("type", `String "string");
                                  ("description", `String "Filter by source LID");
                                ] );
                            ( "target",
                              `Assoc
                                [
                                  ("type", `String "string");
                                  ("description", `String "Filter by target LID");
                                ] );
                            ( "rel",
                              `Assoc
                                [
                                  ("type", `String "string");
                                  ( "enum",
                                    `List
                                      (List.map
                                         (fun s -> `String s)
                                         [
                                           "linked_to";
                                           "belongs_to";
                                           "contains";
                                           "triggered_by";
                                           "deployed_via";
                                           "reviewed_by";
                                           "assigned_to";
                                           "references";
                                         ]) );
                                  ( "description",
                                    `String
                                      "Filter by rel. linked_to: issue↔mr via \
                                       DevStatus. belongs_to: issue in sprint. \
                                       contains: sprint has issues. \
                                       triggered_by: pipeline from mr. \
                                       deployed_via: issue in deploy. \
                                       reviewed_by: mr reviewer. \
                                       assigned_to: assignee."
                                  );
                                ] );
                            ( "limit",
                              `Assoc
                                [
                                  ("type", `String "integer");
                                  ( "description",
                                    `String
                                      "Max results to return. Default 100, max \
                                       1000." );
                                ] );
                            ( "offset",
                              `Assoc
                                [
                                  ("type", `String "integer");
                                  ( "description",
                                    `String
                                      "Skip first N results for pagination." );
                                ] );
                          ] );
                    ] );
              ];
            (* status *)
            `Assoc
              [
                ("name", `String "status");
                ( "description",
                  `String
                    "Get diagnostics: entity count, resolved/pending ref \
                     counts, and list of missing entities blocking resolution. \
                     Call this to understand what data is still needed." );
                ( "parameters",
                  `Assoc
                    [ ("type", `String "object"); ("properties", `Assoc []) ] );
              ];
          ] );
    ]

(** Tool schemas as a formatted JSON string, ready for system prompt injection.
*)
let tool_schemas_string () : string =
  Yojson.Safe.pretty_to_string (tool_schemas ())
