(lang dune 3.20)

(name aimemory)

; x-release-please-start-version
(version 0.1.0)
; x-release-please-end

(generate_opam_files true)

(authors "Sergey Avdienko")

(maintainers "Sergey Avdienko")

(license MIT)

(homepage "https://github.com/AvdienkoSergey/aimemory")

(bug_reports "https://github.com/AvdienkoSergey/aimemory/issues")

(package
 (name aimemory)
 (synopsis "Context memory for AI agents")
 (description "SQLite-based context memory system for AI agents with entity storage, references and queries")
 (depends
  (ocaml (>= 5.1))
  (dune (>= 3.20))
  sqlite3
  yojson
  sexplib0
  logs
  fmt
  (ounit2 :with-test)
  (qcheck-core :with-test)
  (qcheck-ounit :with-test)))
