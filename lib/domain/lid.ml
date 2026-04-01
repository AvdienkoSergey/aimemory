type t = { kind : kind; path : string } [@@deriving compare, equal, hash]

(* When adding a new variant: update prefix_of_kind, kind_of_prefix, AND
   all_kinds *)
and kind =
  (* Jira entities *)
  | Issue       (** задача/тикет, e.g. issue:DBO-123 *)
  | Epic        (** эпик, e.g. epic:DBO-100 *)
  | Sprint      (** спринт, e.g. sprint:42 *)
  | Board       (** доска, e.g. board:5 *)
  | Version     (** версия/релиз Jira, e.g. version:1.2.3 *)
  | JiraProject (** проект Jira, e.g. jproject:DBO *)
  | JiraUser    (** пользователь Jira, e.g. juser:ivan.petrov *)
  (* GitLab entities *)
  | MergeRequest (** merge request, e.g. mr:backend/456 *)
  | Pipeline     (** пайплайн CI/CD, e.g. pipeline:789 *)
  | Job          (** шаг пайплайна, e.g. job:1234 *)
  | Commit       (** коммит, e.g. commit:abc123def *)
  | Branch       (** ветка, e.g. branch:feature/login *)
  | Deployment   (** деплой, e.g. deploy:prod/2024-01 *)
  | Release      (** релиз GitLab, e.g. release:v1.2.3 *)
  | GlProject    (** проект GitLab, e.g. glproject:backend *)
  | GlUser       (** пользователь GitLab, e.g. gluser:ivan.petrov *)
  | Milestone    (** майлстоун, e.g. milestone:Q1-2025 *)

type parse_error = Empty | Missing_colon | Unknown_kind of string | Empty_path

let prefix_of_kind = function
  | Issue -> "issue"
  | Epic -> "epic"
  | Sprint -> "sprint"
  | Board -> "board"
  | Version -> "version"
  | JiraProject -> "jproject"
  | JiraUser -> "juser"
  | MergeRequest -> "mr"
  | Pipeline -> "pipeline"
  | Job -> "job"
  | Commit -> "commit"
  | Branch -> "branch"
  | Deployment -> "deploy"
  | Release -> "release"
  | GlProject -> "glproject"
  | GlUser -> "gluser"
  | Milestone -> "milestone"

(* IMPORTANT: Update this list when adding a new kind variant! The compiler
   won't warn — pattern matching in prefix_of_kind/kind_of_prefix will catch
   missing cases, but this list must be updated manually. *)
let all_kinds =
  [
    Issue;
    Epic;
    Sprint;
    Board;
    Version;
    JiraProject;
    JiraUser;
    MergeRequest;
    Pipeline;
    Job;
    Commit;
    Branch;
    Deployment;
    Release;
    GlProject;
    GlUser;
    Milestone;
  ]

(* Derived from prefix_of_kind + all_kinds — no manual maintenance *)
let kind_of_prefix s = List.find_opt (fun k -> prefix_of_kind k = s) all_kinds

let of_string s =
  if String.length s = 0 then
    Error Empty
  else
    match String.index_opt s ':' with
    | None -> Error Missing_colon
    | Some i -> (
        let prefix = String.sub s 0 i in
        let path = String.sub s (i + 1) (String.length s - i - 1) in
        if String.length path = 0 then
          Error Empty_path
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
