(* WHY fixed rel types? Enables queries like "show all issues linked to MRs". *)
type rel =
  | Linked_to    (** issue linked_to mr — через DevStatus API / ключ в тексте *)
  | Belongs_to   (** issue belongs_to sprint; mr belongs_to pipeline *)
  | Contains     (** sprint contains issue; pipeline contains job *)
  | Triggered_by (** pipeline triggered_by mr — CI событие *)
  | Deployed_via (** issue deployed_via deployment — попал в прод *)
  | Reviewed_by  (** mr reviewed_by gluser — участник ревью *)
  | Assigned_to  (** issue/mr assigned_to juser/gluser *)
  | References   (** generic fallback — когда ни одна из выше не подходит *)

type pending = { source : Lid.t; target : Lid.t; rel : rel }

type resolved = {
  source : Lid.t;
  target : Lid.t;
  rel : rel;
  source_id : int;
  target_id : int;
}

(* WHY not Ok/Error? Target_missing is normal - AI can describe entities in any
   order. *)
type resolution =
  | Resolved of resolved
  | Source_missing of pending
  | Target_missing of pending
  | Both_missing of pending

let rel_to_string = function
  | Linked_to -> "linked_to"
  | Belongs_to -> "belongs_to"
  | Contains -> "contains"
  | Triggered_by -> "triggered_by"
  | Deployed_via -> "deployed_via"
  | Reviewed_by -> "reviewed_by"
  | Assigned_to -> "assigned_to"
  | References -> "references"

let all_rels =
  [
    Linked_to;
    Belongs_to;
    Contains;
    Triggered_by;
    Deployed_via;
    Reviewed_by;
    Assigned_to;
    References;
  ]

(* Derived from rel_to_string + all_rels — no manual maintenance *)
let rel_of_string s = List.find_opt (fun r -> rel_to_string r = s) all_rels
