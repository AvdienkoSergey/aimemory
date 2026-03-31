(** Logging infrastructure for aimemory.

    Features:
    - File logging with rotation (max 10MB)
    - Errors also go to stderr
    - Human-readable format with timestamps
    - Log file path derived from database path *)

let src = Logs.Src.create "aimemory" ~doc:"AI Memory system"

module Log = (val Logs.src_log src : Logs.LOG)

(* Re-export for convenience *)
let debug msgf = Log.debug msgf
let info msgf = Log.info msgf
let warn msgf = Log.warn msgf
let err msgf = Log.err msgf

(* ── File rotation ── *)

let max_log_size = 10 * 1024 * 1024 (* 10 MB *)

let rotate_if_needed path =
  try
    let stats = Unix.stat path in
    if stats.Unix.st_size > max_log_size then begin
      let backup = path ^ ".old" in
      (try Unix.unlink backup with Unix.Unix_error _ -> ());
      Unix.rename path backup
    end
  with Unix.Unix_error _ -> ()

(* ── Reporter ── *)

let pp_timestamp ppf () =
  let open Unix in
  let t = localtime (gettimeofday ()) in
  Format.fprintf ppf "%04d-%02d-%02d %02d:%02d:%02d" (t.tm_year + 1900)
    (t.tm_mon + 1) t.tm_mday t.tm_hour t.tm_min t.tm_sec

let pp_level ppf level =
  let s =
    match level with
    | Logs.App -> "APP"
    | Logs.Error -> "ERROR"
    | Logs.Warning -> "WARN"
    | Logs.Info -> "INFO"
    | Logs.Debug -> "DEBUG"
  in
  Format.fprintf ppf "%-5s" s

(** Reporter that writes to file + stderr for errors. Uses a buffer to capture
    message, then writes to file (and stderr for errors). *)
let file_reporter ~file_path () =
  rotate_if_needed file_path;
  let oc =
    open_out_gen [ Open_append; Open_creat; Open_text ] 0o644 file_path
  in
  let file_ppf = Format.formatter_of_out_channel oc in
  let buf = Buffer.create 256 in
  let buf_ppf = Format.formatter_of_buffer buf in
  let report _src level ~over k msgf =
    Buffer.clear buf;
    let finish _ =
      Format.pp_print_flush buf_ppf ();
      let msg = Buffer.contents buf in
      (* Write to file with timestamp *)
      Format.fprintf file_ppf "%a [%a] %s@." pp_timestamp () pp_level level msg;
      Format.pp_print_flush file_ppf ();
      (* Errors also go to stderr *)
      if level = Logs.Error then Format.eprintf "[ERROR] %s@." msg;
      over ();
      k ()
    in
    msgf @@ fun ?header:_ ?tags:_ fmt -> Format.kfprintf finish buf_ppf fmt
  in
  { Logs.report }

(** Derive log path from db path: "context.db" => "context.log" *)
let log_path_of_db_path db_path =
  let base = Filename.remove_extension db_path in
  base ^ ".log"

(* ── Setup ── *)

type config = { db_path : string; level : Logs.level option }

let default_config = { db_path = "context.db"; level = Some Logs.Info }

let setup ?(config = default_config) () =
  let log_path = log_path_of_db_path config.db_path in
  Logs.set_reporter (file_reporter ~file_path:log_path ());
  Logs.set_level config.level;
  info (fun m -> m "Logging initialized, file: %s" log_path);
  log_path

let shutdown () =
  info (fun m -> m "Shutting down");
  (* Flush is handled by reporter *)
  ()
