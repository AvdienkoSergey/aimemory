# Contributing to aimemory

Thank you for your interest in the project! This document describes the development process and rules for making changes.

## Branching Strategy

The project uses **GitHub Flow**:

1. `main` — stable branch, always in working state
2. For each task, create a **feature branch** from `main`
3. Changes go through a **Pull Request** with required code review
4. After PR is approved, it is merged to `main` with squash merge

### Branch naming

```
feat/short-description       — new feature
fix/short-description        — bug fix
docs/short-description       — documentation changes
refactor/short-description   — refactoring without behavior change
test/short-description       — adding or changing tests
```

## Commit Convention

The project uses [Conventional Commits](https://www.conventionalcommits.org/) to automatically create CHANGELOG and manage versions:

```
feat: add new entity kind for function signatures
fix: resolve UNIQUE constraint error on duplicate emit
docs: update CLI usage examples
test: add property-based tests for Lid parsing
refactor: simplify Resolver graph traversal
chore: update dependencies
```

## Development Workflow

### Setting up the environment

```bash
git clone https://github.com/AvdienkoSergey/aimemory.git
cd aimemory
opam install . --deps-only --with-test
dune build
```

### Before sending a PR

```bash
dune build                                          # compiles without errors
opam lint aimemory.opam                             # opam file is valid
dune build @fmt                                     # formatting is correct
dune runtest                                        # all tests pass
dune runtest --instrument-with bisect_ppx           # coverage check
```

### Auto-fix formatting

```bash
dune fmt
```

## Code Review

- Each PR needs at least one approve from a code owner
- CI must be green before merge
- Reviewer checks: correctness, tests, documentation, code style
- PR author must resolve all comments

## Code Style

- Formatting with `ocamlformat` (config in `.ocamlformat`)
- Run `dune build @fmt` to check, `dune fmt` to auto-fix
- Keep modules small and focused
- Prefer simple code over clever abstractions

## Testing

- Unit tests for each module (`test/test_*.ml`)
- Property-based tests with `qcheck` for edge cases (`test/test_prop.ml`)
- Code coverage is checked in CI with `bisect_ppx`

## Reporting Issues

- Use Issue templates on GitHub
- **Bug Report** — for bugs
- **Feature Request** — for ideas

## Releases

Releases are managed automatically with [release-please](https://github.com/googleapis/release-please). When you merge to `main`, a PR with version update and CHANGELOG is created.

## Code of Conduct

Please read and follow the [Code of Conduct](CODE_OF_CONDUCT.md).
