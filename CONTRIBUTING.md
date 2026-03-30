# Contributing

## How to Create an Issue

### Bug Report with Logs

1. Run the command with `--verbose` flag:
```bash
aimemory --verbose call emit '{"entities":[...]}'
```

2. Find the log file (it is next to database):
```bash
# If database is context.db, logs are in context.log
cat context.log
```

3. Create an issue with:
   - **Title:** short description of the problem
   - **Steps:** what commands you ran
   - **Expected:** what should happen
   - **Actual:** what happened
   - **Logs:** copy from `.log` file

**Example issue:**

```markdown
### Steps
aimemory --verbose call emit '{"entities":[{"lid":"fn:test","data":{}}]}'

### Expected
Entity is saved without errors

### Actual
Error "Storage_error: UNIQUE constraint failed"

### Logs
2024-01-15 10:23:45 [DEBUG] processing command: emit (1 entities)
2024-01-15 10:23:45 [WARN] command emit failed: storage error: UNIQUE constraint failed
```

### Feature Request

- Describe why you need this feature
- Give an example (CLI command, JSON format)
- Tell us what new kind or rel types you need

## How to Create a Pull Request

### Before You Start

1. Make sure the project builds and tests pass:
```bash
dune build
dune runtest
```

### Steps

1. Create a new branch from `main`:
```bash
git checkout -b feature/my-feature
```

2. Make your changes. Keep the code simple:
   - Simple code is better than "clever" code
   - Do not add extra abstractions
   - Code should be easy to read

3. Check that everything works:
```bash
dune build
dune runtest
```

4. Create a commit with a clear message:
```bash
git add .
git commit -m "feat: add X for Y"
```

5. Push your branch and create a PR:
```bash
git push -u origin feature/my-feature
gh pr create --title "feat: add X" --body "..."
```

### PR Format

```markdown
## What I did
- Short list of changes

## Why
- What problem this solves

## How to test
- Commands to check it works
```

### Checklist Before PR

- [ ] `dune build` works without errors
- [ ] `dune runtest` — all tests pass
- [ ] I added tests for new code (if needed)
- [ ] I updated README if public API changed

## Project Structure

```
lib/
  domain/    — types: Lid, Entity, Ref, Protocol
  storage/   — SQLite: Repo, Schema
  engine/    — logic: Ingest, Resolver
  api/       — JSON API: Tools
  support/   — helpers: Log
bin/
  main.ml    — CLI
test/
  test_*.ml  — tests
```

## How to Add a New Kind

1. Add a new variant in `lib/domain/lid.ml`:
```ocaml
type kind =
  | ...
  | MyNewKind  (* new kind *)
```

2. Update `prefix_of_kind` and `kind_of_prefix`

3. Add it to `all_kinds` list

4. The compiler will show you all places where you need to handle the new kind
