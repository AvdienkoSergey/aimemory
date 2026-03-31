(** Ingest — command processor and pipeline orchestrator.

    This is the single entry point for the engine layer. Takes
    [Protocol.command], executes against [Repo.t], returns [Protocol.response].

    Pipeline for [Emit]: 1. Extract entities and refs from [entity_input] list
    2. Upsert all entities in a transaction 3. Insert all pending refs 4. Run
    resolver to link what's possible 5. Return [emit_result] with
    resolved/pending split

    Type contract:
    - Input: [Protocol.command] — pure data, no IO
    - Output: [Protocol.response] — pure data, no IO
    - Side effects: all go through [Repo.t] *)

(** {1 Internal handlers} *)

let process_emit (db : Repo.t) (inputs : Protocol.entity_input list) :
    Protocol.response =
  (* Step 1: extract raw entities *)
  let raws : Entity.raw list =
    List.map
      (fun (ei : Protocol.entity_input) ->
        Entity.{ lid = ei.lid; data = ei.data })
      inputs
  in
  (* Step 2: extract pending refs from each input *)
  let all_pending : Ref.pending list =
    List.concat_map
      (fun (ei : Protocol.entity_input) ->
        List.map
          (fun (ri : Protocol.ref_input) ->
            Ref.{ source = ei.lid; target = ri.target; rel = ri.rel })
          ei.refs)
      inputs
  in
  (* Step 3: upsert entities *)
  match Repo.upsert_many db raws with
  | Error e -> Protocol.Error (Storage_error (Repo.pp_error e))
  | Ok stored -> (
      (* Step 4: insert pending refs *)
      match Repo.insert_refs db all_pending with
      | Error e -> Protocol.Error (Storage_error (Repo.pp_error e))
      | Ok () -> (
          (* Step 5: resolve refs *)
          match Resolver.resolve_all db with
          | Error e -> Protocol.Error (Storage_error (Repo.pp_error e))
          | Ok resolution ->
              let upserted =
                List.map (fun (s : Entity.processed) -> s.lid) stored
              in
              Protocol.Emit_result
                {
                  upserted;
                  refs_resolved = resolution.resolved;
                  refs_pending = resolution.pending;
                }))

let process_query_entities (db : Repo.t) (q : Protocol.entity_query) :
    Protocol.response =
  match Resolver.query_entities db q with
  | Ok entities -> Protocol.Entities entities
  | Error e -> Protocol.Error (Storage_error (Repo.pp_error e))

let process_query_refs (db : Repo.t) (q : Protocol.ref_query) :
    Protocol.response =
  match Resolver.query_refs db q with
  | Ok refs -> Protocol.Refs refs
  | Error e -> Protocol.Error (Storage_error (Repo.pp_error e))

(** {1 Pipeline — main entry point} *)

(** Process a single command. *)
let process (db : Repo.t) (cmd : Protocol.command) : Protocol.response =
  let cmd_name =
    match cmd with
    | Emit { entities } ->
        Printf.sprintf "emit (%d entities)" (List.length entities)
    | Query_entities _ -> "query_entities"
    | Query_refs _ -> "query_refs"
  in
  Log.debug (fun m -> m "processing command: %s" cmd_name);
  let result =
    match cmd with
    | Emit { entities } -> process_emit db entities
    | Query_entities q -> process_query_entities db q
    | Query_refs q -> process_query_refs db q
  in
  (match result with
  | Protocol.Error e ->
      let msg =
        match e with
        | Protocol.Invalid_lid (s, _) -> "invalid lid: " ^ s
        | Protocol.Storage_error s -> "storage error: " ^ s
        | Protocol.Unknown_command s -> "unknown command: " ^ s
      in
      Log.warn (fun m -> m "command %s failed: %s" cmd_name msg)
  | _ -> ());
  result

(** {1 Batch processing} *)

(** Process multiple commands sequentially. Stops on first error, returns all
    responses up to that point. *)
let process_batch (db : Repo.t) (cmds : Protocol.command list) :
    Protocol.response list =
  let rec loop acc = function
    | [] -> List.rev acc
    | cmd :: rest -> (
        let resp = process db cmd in
        match resp with
        | Protocol.Error _ -> List.rev (resp :: acc)
        | _ -> loop (resp :: acc) rest)
  in
  loop [] cmds

(** Process multiple commands, collecting all responses regardless of errors. *)
let process_all (db : Repo.t) (cmds : Protocol.command list) :
    Protocol.response list =
  List.map (process db) cmds

(** {1 Convenience wrappers} *)

(** Emit a single entity with no refs. *)
let emit_one (db : Repo.t) ~lid ~data : Protocol.response =
  let input = Protocol.{ lid; data; refs = [] } in
  process db (Emit { entities = [ input ] })

(** Emit a single entity with refs. *)
let emit_with_refs (db : Repo.t) ~lid ~data ~refs : Protocol.response =
  let ref_inputs =
    List.map (fun (target, rel) -> Protocol.{ target; rel }) refs
  in
  let input = Protocol.{ lid; data; refs = ref_inputs } in
  process db (Emit { entities = [ input ] })

(** Query all entities of a specific kind. *)
let query_by_kind (db : Repo.t) (kind : Lid.kind) : Protocol.response =
  process db
    (Query_entities
       { kind = Some kind; pattern = None; limit = None; offset = None })

(** Query entities matching a glob pattern. *)
let query_by_pattern (db : Repo.t) ?kind (pattern : string) : Protocol.response
    =
  process db
    (Query_entities
       { kind; pattern = Some pattern; limit = None; offset = None })

(** Get all refs originating from a given entity. *)
let outgoing_refs (db : Repo.t) (source : Lid.t) : Protocol.response =
  process db
    (Query_refs
       {
         source = Some source;
         target = None;
         rel_type = None;
         limit = None;
         offset = None;
       })

(** Get all refs pointing to a given entity. *)
let incoming_refs (db : Repo.t) (target : Lid.t) : Protocol.response =
  process db
    (Query_refs
       {
         source = None;
         target = Some target;
         rel_type = None;
         limit = None;
         offset = None;
       })

(** {1 Diagnostics} *)

type status = { stats : Repo.stats; missing : Resolver.missing_analysis }
(** Full status report: stats + missing analysis. *)

let status (db : Repo.t) : (status, Repo.error) result =
  match Repo.stats db with
  | Error e -> Error e
  | Ok stats -> (
      match Resolver.analyze_pending db with
      | Error e -> Error e
      | Ok missing -> Ok { stats; missing })

let pp_status (s : status) : string =
  Printf.sprintf "Entities: %d | Refs resolved: %d | Refs pending: %d\n%s"
    s.stats.entity_count s.stats.ref_resolved_count s.stats.ref_pending_count
    (Resolver.pp_missing_analysis s.missing)
