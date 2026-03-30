type t = { kind : kind; path : string } [@@deriving compare, equal, hash]

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

let kind_of_prefix = function
  | "comp" -> Some Comp
  | "view" -> Some View
  | "layout" -> Some Layout
  | "store" -> Some Store
  | "service" -> Some Service
  | "composable" -> Some Composable
  | "intercept" -> Some Intercept
  | "validator" -> Some Validator
  | "util" -> Some Util
  | "plugin" -> Some Plugin
  | "provider" -> Some Provider
  | "route" -> Some Route
  | "locale" -> Some Locale
  | "const" -> Some Const
  | "style" -> Some Style
  | "unit" -> Some Unit
  | "e2e" -> Some E2e
  | "asset" -> Some Asset
  | "api" -> Some Api
  | "dep" -> Some Dep
  | "fn" -> Some Fn
  | "state" -> Some State
  | "computed" -> Some Computed
  | "action" -> Some Action
  | "prop" -> Some Prop
  | "emit" -> Some Emit
  | "hook" -> Some Hook
  | "type" -> Some Typ
  | "provide" -> Some Provide
  | _ -> None

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
  let sexp_of_t t = Sexplib0.Sexp.Atom (to_string t)
end

module Map = Map.Make (T)
module Set = Set.Make (T)
