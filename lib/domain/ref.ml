(* WHY fixed rel types? Enables queries like "show all calls". *)
type rel =
  | Belongs_to   (** fn belongs_to composable — parent-child *)
  | Calls        (** useAuth calls loginAPI — function invocation *)
  | Depends_on   (** Button depends_on lodash — import/require *)
  | Contains     (** file contains function — structural nesting *)
  | Implements   (** validate implements Validator — type conformance *)
  | References   (** generic link when nothing else fits *)

type pending = {
  source : Lid.t;
  target : Lid.t;
  rel : rel;
}

type resolved = {
  source : Lid.t;
  target : Lid.t;
  rel : rel;
  source_id : int;
  target_id : int;
}

(* WHY not Ok/Error? Target_missing is normal - AI can describe code in any order. *)
type resolution =
  | Resolved of resolved
  | Source_missing of pending
  | Target_missing of pending
  | Both_missing of pending

let rel_to_string = function
  | Belongs_to -> "belongs_to"
  | Calls -> "calls"
  | Depends_on -> "depends_on"
  | Contains -> "contains"
  | Implements -> "implements"
  | References -> "references"

let rel_of_string = function
  | "belongs_to" -> Some Belongs_to
  | "calls" -> Some Calls
  | "depends_on" -> Some Depends_on
  | "contains" -> Some Contains
  | "implements" -> Some Implements
  | "references" -> Some References
  | _ -> None
