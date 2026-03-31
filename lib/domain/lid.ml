type t = { kind : kind; path : string } [@@deriving compare, equal, hash]

(* When adding a new variant: update prefix_of_kind, kind_of_prefix, AND all_kinds *)
and kind =
  | Comp
  | View
  | Layout
  | Store
  | Service
  | Composable
  | Intercept
  | Validator
  | Util
  | Plugin
  | Provider
  | Route
  | Locale
  | Const
  | Style
  | Unit
  | E2e
  | Asset
  | Api
  | Dep
  | Fn
  | State
  | Computed
  | Action
  | Prop
  | Emit
  | Hook
  | Typ
  | Provide

type parse_error = Empty | Missing_colon | Unknown_kind of string | Empty_path

let prefix_of_kind = function
  | Comp -> "comp"
  | View -> "view"
  | Layout -> "layout"
  | Store -> "store"
  | Service -> "service"
  | Composable -> "composable"
  | Intercept -> "intercept"
  | Validator -> "validator"
  | Util -> "util"
  | Plugin -> "plugin"
  | Provider -> "provider"
  | Route -> "route"
  | Locale -> "locale"
  | Const -> "const"
  | Style -> "style"
  | Unit -> "unit"
  | E2e -> "e2e"
  | Asset -> "asset"
  | Api -> "api"
  | Dep -> "dep"
  | Fn -> "fn"
  | State -> "state"
  | Computed -> "computed"
  | Action -> "action"
  | Prop -> "prop"
  | Emit -> "emit"
  | Hook -> "hook"
  | Typ -> "type"
  | Provide -> "provide"

(* IMPORTANT: Update this list when adding a new kind variant!
   The compiler won't warn — pattern matching in prefix_of_kind/kind_of_prefix
   will catch missing cases, but this list must be updated manually. *)
let all_kinds =
  [
    Comp;
    View;
    Layout;
    Store;
    Service;
    Composable;
    Intercept;
    Validator;
    Util;
    Plugin;
    Provider;
    Route;
    Locale;
    Const;
    Style;
    Unit;
    E2e;
    Asset;
    Api;
    Dep;
    Fn;
    State;
    Computed;
    Action;
    Prop;
    Emit;
    Hook;
    Typ;
    Provide;
  ]

(* Derived from prefix_of_kind + all_kinds — no manual maintenance *)
let kind_of_prefix s =
  List.find_opt (fun k -> prefix_of_kind k = s) all_kinds

let of_string s =
  if String.length s = 0 then Error Empty
  else
    match String.index_opt s ':' with
    | None -> Error Missing_colon
    | Some i -> (
        let prefix = String.sub s 0 i in
        let path = String.sub s (i + 1) (String.length s - i - 1) in
        if String.length path = 0 then Error Empty_path
        else
          match kind_of_prefix prefix with
          | None -> Error (Unknown_kind prefix)
          | Some kind -> Ok { kind; path })

let make kind ~path = { kind; path }
let to_string { kind; path } = prefix_of_kind kind ^ ":" ^ path
let kind { kind; _ } = kind
let path { path; _ } = path

let pp_parse_error = function
  | Empty -> "empty string"
  | Missing_colon -> "missing colon separator"
  | Unknown_kind k -> "unknown kind: " ^ k
  | Empty_path -> "empty path after colon"

module T = struct
  type nonrec t = t

  let compare = compare
  let _sexp_of_t t = Sexplib0.Sexp.Atom (to_string t)
end

module Map = Map.Make (T)
module Set = Set.Make (T)
