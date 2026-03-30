(* WHY list of pairs? Domain layer is source-agnostic (JSON, YAML, etc.) *)
type data = (string * value) list

(* WHY no Object type? Nested objects must be separate entities. *)
and value =
  | String of string
  | Int of int
  | Float of float
  | Bool of bool
  | List of value list
  | Null

type raw = { lid : Lid.t; data : data }

type processed = {
  id : int;
  lid : Lid.t;
  data : data;
  created : float;
  updated : float;
}
