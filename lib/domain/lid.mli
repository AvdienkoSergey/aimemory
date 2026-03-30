(**
    Logical ID = lid = unique name for each thing in your code
    LID is like URN (Uniform Resource Name) for things in the project
    It works as root:path. For example, lid fn:useAuth:auth tells me:
    this is a function from file useAuth, and the name is auth
*)
type t [@@deriving compare, equal, hash]

(** Kind of thing, saved in LID prefix *)
type kind =
  (* Level 1 — modules *)
  | Comp  (** comp:... — Vue component *)
  | View  (** view:... — Router page *)
  | Layout  (** layout:... — Layout wrapper *)
  | Store  (** store:... — Pinia store *)
  | Service  (** service:... — Service layer *)
  | Composable  (** composable:... — Vue composable *)
  | Intercept  (** intercept:... — Axios interceptor *)
  | Validator  (** validator:... — Validator *)
  | Util  (** util:... — Utility module *)
  | Plugin  (** plugin:... — Vue plugin *)
  | Provider  (** provider:... — Provider *)
  | Route  (** route:... — Router entry *)
  | Locale  (** locale:... — i18n locale *)
  | Const  (** const:... — Constants *)
  | Style  (** style:... — Styles *)
  | Unit  (** unit:... — Unit test *)
  | E2e  (** e2e:... — E2E test *)
  | Asset  (** asset:... — Static asset *)
  | Api  (** api:... — API definition *)
  | Dep  (** dep:... — npm package from outside *)
  (* Level 2 — things inside modules *)
  | Fn  (** fn:... — function or method *)
  | State  (** state:... — reactive state *)
  | Computed  (** computed:... — computed state *)
  | Action  (** action:... — state change *)
  | Prop  (** prop:... — input for component *)
  | Emit  (** emit:... — event from component *)
  | Hook  (** hook:... — lifecycle hook *)
  | Typ  (** type:... — TypeScript type/interface/enum *)
  | Provide  (** provide:... — provide/inject key *)

(**
    Why do we have a type for errors?
    It helps us to handle each error in its own way
    match Lid.of_string input with
        | Ok lid -> (* do work *)
        | Error Empty -> (* say it is empty *)
        | Error Missing_colon -> (* say about format *)
        | Error (Unknown_kind k) -> (* say which kind is bad *)
        | Error Empty_path -> (* say path is needed *)
*)
type parse_error =
    | Empty (* empty string *)
    | Missing_colon (* no colon as separator *)
    | Unknown_kind of string (* kind we do not know *)
    | Empty_path (* path is empty *)

val of_string : string -> (t, parse_error) result
val make : kind -> path:string -> t
(* lid => "comp:ui/Button" *)
val to_string : t -> string
(* lid => Comp *)
val kind : t -> kind
(* lid => "ui/Button" *)
val path : t -> string
val all_kinds : kind list
val prefix_of_kind : kind -> string
val pp_parse_error : parse_error -> string

(** Example: Give me the thing by its LID *)
module Map : Map.S with type key = t
(** Example: Did we see this LID before? Collect all unique lids *)
module Set : Set.S with type elt = t
