# AGENTS.md

This repository is `logwatch`, a web server access log analyser written in
the Loup programming language, part of the loup-cmd series of example
applications. It is a `host.scripted` project: the programs are `.lpscr`
scripts in `bin/` that `loup run` executes from source, and they import
shared `host.dual` modules from `lib/`. Nothing is compiled.

## Skills

| Skill | Location | Use it when |
|-------|----------|-------------|
| `loup-programmer` | [skills/loup-programmer/SKILL.md](skills/loup-programmer/SKILL.md) | Writing, reviewing, debugging or explaining Loup code: `.lpscr`, `.loup`, `.lphc`, `.lpweb` or `.lpfree` source files, `.lppkg` manifests, `@mode(...)` directives, or the `loup` / `loup-bootstrap` commands. |

Read `skills/loup-programmer/SKILL.md` before writing or changing any Loup code
in this repository. It links to detailed references under
`skills/loup-programmer/references/` for syntax, types and ownership, execution
modes and projects, errors and diagnostics, the standard library, and common
mistakes. Load those only as needed.

## Code layout

```text
.
├── package.lppkg                # manifest: name, version, toolchain, [build] entry (bin/logwatch.lpscr), [test] pattern
├── Makefile                     # run, gen, check, test, e2e, ci, clean
├── bin/                         # entry scripts (host.scripted, executable, shebang `loup run`)
│   ├── logwatch.lpscr           # the analyser: arguments, input files, output, exit status
│   └── loggen.lpscr             # synthetic log generator
├── lib/                         # shared modules; host.dual unless noted
│   ├── appinfo.loup             # APP_NAME, APP_VERSION, APP_SUMMARY, exit statuses
│   ├── args.loup                # struct Options, parse_args()
│   ├── usage.loup               # usage(), version_line()
│   ├── clf.loup                 # Stamp, Request, Entry, class ClfParser (system.regex), format_entry()
│   ├── stats.loup               # Tally, Minute, class Stats (counters)
│   ├── analyse.loup             # class Analyser: feed(name, text) → stats and problems
│   ├── reports.loup             # enum Cell, struct Table, one *_table() per report, build_reports()
│   ├── render.loup              # render_text(), render_csv()
│   ├── render_json.lpscr        # render_json(): host.scripted, because it uses Any
│   └── sample.loup              # generate(), parse_gen_args() for loggen
├── tests/
│   ├── *_test.lpscr             # unit tests: func test_*(): void
│   ├── e2e.sh                   # end-to-end tests: runs the scripts with loup run
│   ├── fixtures/access.log      # sample log (both formats, malformed lines, a burst)
│   └── expected/                # the fixture's full reports: access.txt, .csv, .json
├── specs/logwatch/              # requirements.md, design.md, tasks.md
├── skills/loup-programmer/      # the Loup skill and its references
└── .github/workflows/ci.yml     # installs Loup and runs `make ci`
```

## Check, run and test

Prerequisites: Loup 1.26.0 (`loup` and `loup-bootstrap` on `PATH`), `make`
and `bash`.

| Task | Command | Notes |
|------|---------|-------|
| Run from source | `make run ARGS="-r paths tests/fixtures/access.log"` | `loup run bin/logwatch.lpscr -- ARGS` |
| Run directly | `./bin/logwatch.lpscr -f csv FILE` | long options only after `--` (see below) |
| Sample log | `make -s gen ARGS="-n 5000 -s 7" > sample.log` | `loup run bin/loggen.lpscr -- ARGS` |
| Type-check | `make check` | `loup-bootstrap check FILE` for each `bin/*.lpscr` and the modules it imports |
| Unit tests | `make test` | each `tests/*_test.lpscr` in turn |
| One test file | `make test TESTS=tests/clf_test.lpscr` | |
| Matching tests | `make test TEST_ARGS="--filter burst"` | tests whose name contains `burst` |
| End-to-end tests | `make e2e` | `tests/e2e.sh`: output and exit status of `loup run` |
| Everything CI runs | `make ci` | check, test, e2e, then `--version` |
| Clean | `make clean` | removes `.temp/` |

Run `make ci` before reporting a change as done. Unit tests run under Stage0
(`loup-bootstrap`); the scripts run under the self-hosted `loup run`, which
behaves differently in places (below), so only `make e2e` shows what users get.

Toolchain facts this project depends on (Loup 1.26.0, Linux x86-64):

- A script entry cannot be built (`E-BUILD-COMPILED`), so there is no build
  target. `loup-bootstrap check FILE` does type-check a script and its
  imports; `[build] entry` points at `bin/logwatch.lpscr`.
- `loup run SCRIPT --long` treats `--long` as its own flag; the self-hosted
  driver drops it silently. Script options go after `--`:
  `loup run bin/logwatch.lpscr -- --format json`. Short options pass through.
- The self-hosted `loup run` does not process backslash escapes inside
  `i"..."` strings (`i"a\"b"` prints `a\"b`); Stage0 does, so unit tests do
  not catch it. Keep escapes in plain strings and concatenate.
- The self-hosted `loup run` cannot catch `IoError`; check `exists`/`isDir`
  before `readText`.
- A program that imports `data.csv` gets the CSV parser when it calls
  `system.json.parse`. Do not use `system.json.parse` here.
- `loup-bootstrap test` with all files at once fails random tests with an
  empty `RuntimeError` on a busy machine; the Makefile runs one file at a time.
- The self-hosted `loup test` cannot run tests with relative imports; use
  `make test` (Stage0).

## Making a change

1. Update the spec in `specs/logwatch/` (see [specs/README.md](specs/README.md)).
2. Change the code: behaviour in `lib/`, top-level flow in `bin/`.
3. Add or update unit tests in `tests/` and cases in `tests/e2e.sh`. If a
   report changes, regenerate and review `tests/expected/`:
   `loup run bin/logwatch.lpscr -- -f csv tests/fixtures/access.log > tests/expected/access.csv`
   (likewise `access.txt` with no `-f` and `access.json` with `-f json`).
4. Run `make ci`.
5. Tick the finished tasks in `specs/logwatch/tasks.md`.

Keep behaviour in functions that return values (the renderers return the
whole output), so unit tests can check it; only the `bin/` scripts print,
read files and call `exit`.

## Conventions

- `bin/*.lpscr` are `@mode(host.scripted)` with a `#!/usr/bin/env -S loup run`
  line and the executable bit. Keep them thin: arguments, I/O, exit status.
- `lib/*.loup` are `@mode(host.dual)`: declarations only, no top-level
  statements, no `Any`. `lib/render_json.lpscr` is the one scripted module.
- Imports are relative: `from ..lib.clf import (...)` in `bin/` and `tests/`,
  `from .clf import (...)` inside `lib/`. A script's package root is its own
  directory, so `from lib.clf` would not resolve.
- Struct fields that are assigned after construction must be `pub var`
  (Stage0 rejects assigning a `pub` field).
- A method that changes `this` is `modifier`, and callers wrap the call in
  `safe { ... }`; a function that calls a modifier method on a parameter
  declares it `edits` (`func client(edits dice: Dice)`).
- Keep `APP_VERSION` in `lib/appinfo.loup` equal to `version` in
  `package.lppkg`.
- The skill documents toolchain 1.25.1; this project targets 1.26.0. When
  they disagree, trust the toolchain's behaviour.
