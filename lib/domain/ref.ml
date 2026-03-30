(**
  Ref = link between two things in code

  Like in real life:
  - "John works at Google" => John -[works_at]-> Google
  - "Car has Engine" => Car -[has]-> Engine

  In code:
  - "Button imports Icon" => Button -[Imports]-> Icon
  - "useAuth calls loginAPI" => useAuth -[Calls]-> loginAPI

  Links have direction: A -> B is not same as B -> A
*)

(**
  What kinds of links exist?

  Examples:
  - Belongs_to: function login belongs_to composable useAuth
  - Calls: function useAuth calls function loginAPI
  - Depends_on: component Button depends_on package lodash
  - Contains: file auth.ts contains function login
  - Implements: function validate implements type Validator
  - References: generic link when nothing else fits

  WHY fixed set of link types?
  So we can make useful queries: "show all calls", "who depends on what".
  If link type is just a string, queries are not possible.
*)
type rel =
  | Belongs_to
  | Calls
  | Depends_on
  | Contains
  | Implements
  | References

(**
  Link from AI = "raw" link, not checked yet

  Problem: AI says "useAuth calls loginUser"
  But maybe loginUser does not exist yet!

  We save it as pending. Later when loginUser appears,
  link will become resolved.
*)
type pending = {
  source : Lid.t;  (* link starts here *)
  target : Lid.t;  (* link goes here *)
  rel : rel        (* what kind of link *)
}

(**
  Link after checking = both sides exist for sure

  We checked:
  - source exists in database (has source_id)
  - target exists in database (has target_id)

  Now link is real and can be used for queries.
*)
type resolved = {
  source : Lid.t;
  target : Lid.t;
  rel : rel;
  source_id : int;
  target_id : int;
}

(**
  What can happen when we try to check a link?

  Four cases:
  - Resolved => both sides exist, link is ready
  - Source_missing => we don't know who is linking (weird, should not happen)
  - Target_missing => target not in system yet (normal, will check later)
  - Both_missing => nothing exists yet (rare)

  WHY not just Ok/Error?
  Because Target_missing is not really an error.
  AI can describe code in any order.
  We save pending link and check it later.

  Example:
  1. AI says: useAuth calls loginUser
  2. loginUser not found => Target_missing, save as pending
  3. AI says: here is loginUser
  4. We check pending links => now Resolved!
*)
type resolution =
  | Resolved of resolved
  | Source_missing of pending
  | Target_missing of pending
  | Both_missing of pending

(* Convert rel to string for storage/display *)
let rel_to_string = function
  | Belongs_to -> "belongs_to"
  | Calls -> "calls"
  | Depends_on -> "depends_on"
  | Contains -> "contains"
  | Implements -> "implements"
  | References -> "references"

(* Parse rel from string. Returns None if unknown *)
let rel_of_string = function
  | "belongs_to" -> Some Belongs_to
  | "calls" -> Some Calls
  | "depends_on" -> Some Depends_on
  | "contains" -> Some Contains
  | "implements" -> Some Implements
  | "references" -> Some References
  | _ -> None
