(**
  How we talk to outside systems. For example, AI
  - What commands can go between us and outside system
  - What data we need to send with each command
  - What data we get back from each command
  COMMANDS:
  ┌─────────────────────────────────────────────┐
  │ Emit      = "Save this data"                │
  │ Query     = "Find this data"                │
  └─────────────────────────────────────────────┘
  ANSWERS:
  ┌─────────────────────────────────────────────┐
  │ Result    = "Done, here is what I saved"    │
  │ Entities  = "Here is what I found"          │
  │ Error     = "Failed, because..."            │
  └─────────────────────────────────────────────┘
*)

(** What AI can ask us to do. List of allowed commands *)
type command =
  | Emit of emit_payload (* "Save data" *)
  | Query_entities of entity_query (* "Read entities" *)
  | Query_refs of ref_query (* "Read links" *)
(**
  Command Emit = "Save"
  Example: AI looked at code and says:
  "I found function login in file useAuth. It is async and calls authStore"
  As Emit it looks like this:
  {
    entities = [{
      lid = fn:useAuth:login
      data = [("async", true); ("lines", 15)]
      refs = [{ target = store:auth; rel = Calls }]
    }]
  }
  You can send many things at once — that is why entities is a list
*)
and emit_payload = { entities : entity_input list }
and entity_input = {
  lid : Lid.t; (* who is this *)
  data : Entity.data; (* what to save *)
  refs : ref_input list (* what it links to *)
}
(**
  One link: "this thing is linked to another thing"

  Examples:
  - Button imports Icon        { target = comp:ui/Icon; rel = Imports }
  - useAuth calls login        { target = fn:api:login; rel = Calls }
  - UserCard reads userStore   { target = store:user; rel = Reads }
*)
and ref_input = {
  target : Lid.t; (* link goes to this *)
  rel : Ref.rel (* what kind of link: import? call? *)
}
(**
  Command Query_entities = "Find things"
  Filters are optional. Mix them as you want:
  { kind = None; pattern = None } => give me ALL
  { kind = Some Comp; pattern = None } => give me all components
  { kind = Some Comp; pattern = Some "ui/*" } => give me components from ui folder
  { kind = None; pattern = Some "*Auth*" } => give me all with "Auth" in path
*)
and entity_query = {
  kind : Lid.kind option;  (** filter by type *)
  pattern : string option;  (** glob for path: "auth/*" *)
}
(**
  Command Query_refs = "Find links"
  Three filters = three different questions:
  { source = Some "comp:Button"; target = None; rel_type = None } => what does Button use? (links going out)
  { source = None; target = Some "store:auth"; rel_type = None } => who uses authStore? (links coming in)
  { source = None; target = None; rel_type = Some Imports } => show all imports in project
  { source = Some "comp:Button"; target = None; rel_type = Some Calls } => what functions does Button call?
*)
and ref_query = {
  source : Lid.t option;
  target : Lid.t option;
  rel_type : Ref.rel option;
}
(**
  Answers from system to commands
  Each command gets its own answer type:
  - Emit => Emit_result (what we saved, what links wait)
  - Query_entities => Entities (list of things we found)
  - Query_refs => Refs (list of links we found)
  - Any => Error (if something went wrong)
*)
type response =
  | Emit_result of emit_result
  | Entities of Entity.processed list
  | Refs of Ref.resolved list
  | Error of protocol_error
(**
  Result of Emit command = "Here is what we saved"
  Example: AI sent function useAuth, which calls loginUser.
  But loginUser does not exist in system yet!
  Answer:
  {
    upserted = [fn:useAuth] => we saved useAuth
    refs_resolved = [] => no links to existing things
    refs_pending = [useAuth → loginUser] => waiting for loginUser to appear
  }
  Later AI will send loginUser, and link will work

  WHY split resolved and pending?
  So we do not lose data. AI can describe code in any order.
  Link "A calls B" is valid, even if B is not described yet.
*)
and emit_result = {
  upserted : Lid.t list;  (** saved successfully *)
  refs_resolved : Ref.resolved list;  (** links that we could resolve *)
  refs_pending : Ref.pending list;  (** links waiting for target *)
}
(**
  Protocol errors = "Why it did not work"
  Examples:
  - Invalid_lid ("xyz:broken", Missing_colon) => "you sent bad LID, here is what is wrong"
  - Storage_error "connection lost" => "problem with database, try later"
  - Unknown_command "delete" => "command delete does not exist"

  WHY typed errors?
  So AI (outside system) can understand what to fix, not just "error"
*)
and protocol_error =
  | Invalid_lid of string * Lid.parse_error
  | Storage_error of string
  | Unknown_command of string

(** Convenience: query all entities (no filters) *)
let query_all_entities : entity_query = { kind = None; pattern = None }

(** Convenience: query all refs (no filters) *)
let query_all_refs : ref_query = { source = None; target = None; rel_type = None }
