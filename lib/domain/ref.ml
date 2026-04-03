(* WHY fixed rel types? Enables queries like "show all calls". *)
type rel =
  | Belongs_to  (** fn belongs_to composable — parent-child *)
  | Calls  (** useAuth calls loginAPI — function invocation *)
  | Depends_on  (** Button depends_on lodash — import/require *)
  | Contains  (** file contains function — structural nesting *)
  | Implements  (** validate implements Validator — type conformance *)
  | Renders  (** ParentComp renders ChildComp — template usage *)
  | References  (** generic link when nothing else fits *)
  | Covers  (** test covers function — test-to-code mapping *)

type pending = { source : Lid.t; target : Lid.t; rel : rel }

type resolved = {
  source : Lid.t;
  target : Lid.t;
  rel : rel;
  source_id : int;
  target_id : int;
}

(* WHY not Ok/Error? Target_missing is normal - AI can describe code in any
   order. *)
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
  | Renders -> "renders"
  | References -> "references"
  | Covers -> "covers"

let all_rels =
  [ Belongs_to; Calls; Depends_on; Contains; Implements; Renders; References; Covers ]

(* Derived from rel_to_string + all_rels — no manual maintenance *)
let rel_of_string s = List.find_opt (fun r -> rel_to_string r = s) all_rels
