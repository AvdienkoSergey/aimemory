type t [@@deriving compare, equal, hash]
(** Logical ID: unique name for data entities. Format: kind:path *)

(** Entity kind. When adding a variant: update [prefix_of_kind],
    [kind_of_prefix], AND [all_kinds]. *)
type kind =
  (* Jira entities *)
  | Issue  (** задача/тикет — issue:DBO-123 *)
  | Epic  (** эпик — epic:DBO-100 *)
  | Sprint  (** спринт — sprint:42 *)
  | Board  (** доска — board:5 *)
  | Version  (** версия/релиз Jira — version:1.2.3 *)
  | JiraProject  (** проект Jira — jproject:DBO *)
  | JiraUser  (** пользователь Jira — juser:ivan.petrov *)
  (* GitLab entities *)
  | MergeRequest  (** merge request — mr:backend/456 *)
  | Pipeline  (** пайплайн CI/CD — pipeline:789 *)
  | Job  (** шаг пайплайна — job:1234 *)
  | Commit  (** коммит — commit:abc123def *)
  | Branch  (** ветка — branch:feature/login *)
  | Deployment  (** деплой — deploy:prod/2024-01 *)
  | Release  (** релиз GitLab — release:v1.2.3 *)
  | GlProject  (** проект GitLab — glproject:backend *)
  | GlUser  (** пользователь GitLab — gluser:ivan.petrov *)
  | Milestone  (** майлстоун — milestone:Q1-2025 *)

type parse_error =
  | Empty  (** "" — empty string *)
  | Missing_colon  (** "issueDBO-123" — no ":" separator *)
  | Unknown_kind of string  (** "task:foo" — "task" is not a valid kind *)
  | Empty_path  (** "issue:" — path after ":" is empty *)

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
