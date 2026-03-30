(** Logical ID: unique name for code entities. Format: kind:path *)
type t [@@deriving compare, equal, hash]

(** Entity kind. When adding a variant: update [prefix_of_kind], [kind_of_prefix], AND [all_kinds]. *)
type kind =
  (* Module level *)
  | Comp        (** component *)
  | View        (** router page *)
  | Layout      (** layout wrapper *)
  | Store       (** state store *)
  | Service     (** service layer *)
  | Composable  (** composable/hook *)
  | Intercept   (** interceptor *)
  | Validator   (** validator *)
  | Util        (** utility *)
  | Plugin      (** plugin *)
  | Provider    (** provider *)
  | Route       (** route config *)
  | Locale      (** i18n locale *)
  | Const       (** constants *)
  | Style       (** styles *)
  | Unit        (** unit test *)
  | E2e         (** e2e test *)
  | Asset       (** static asset *)
  | Api         (** API endpoint *)
  | Dep         (** external package *)
  (* Inside module *)
  | Fn          (** function *)
  | State       (** reactive state *)
  | Computed    (** computed value *)
  | Action      (** state mutation *)
  | Prop        (** component prop *)
  | Emit        (** component event *)
  | Hook        (** lifecycle hook *)
  | Typ         (** type/interface *)
  | Provide     (** provide/inject key *)

type parse_error =
  | Empty              (** "" — empty string *)
  | Missing_colon      (** "compButton" — no ":" separator *)
  | Unknown_kind of string  (** "widget:foo" — "widget" is not valid kind *)
  | Empty_path         (** "comp:" — path after ":" is empty *)

val of_string : string -> (t, parse_error) result
val make : kind -> path:string -> t
val to_string : t -> string
val kind : t -> kind
val path : t -> string
val all_kinds : kind list
val prefix_of_kind : kind -> string
val pp_parse_error : parse_error -> string

module Map : Map.S with type key = t
module Set : Set.S with type elt = t
