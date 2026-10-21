# loup-cmd-logwatch

A web server access log analyser written as a [Loup](https://code-craft.ai/references/loup)
script: it reads Common and Combined Log Format and reports the top paths,
the status code mix, an hourly histogram, the busiest clients and bursts of
errors, as text, CSV or JSON.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is a `host.scripted` project: thin `.lpscr` entry scripts in `bin/`
that import shared `host.dual` modules from `lib/`, run with `loup run`.

## Requirements

- [Loup Lite](https://github.com/code-craft-ai-company/loup-releases) 1.26.0
  or later (`loup` and `loup-bootstrap` on `PATH`); see [Installing Loup Lite](#installing-loup-lite).
- `make` and `bash` for the checks and tests. No C compiler: nothing is built.

## Installing Loup Lite

This example is built and tested with **Loup Lite**, the free public build of
the Loup toolchain from [Code Craft AI](https://code-craft.ai), meant for
education and training. Code Craft AI publishes the official builds,
installers and signed checksums at
**<https://github.com/code-craft-ai-company/loup-releases>**, for Linux
(x86-64, arm64), macOS (Apple silicon, Intel) and Windows (x86-64).

Linux and macOS:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.ps1 | iex
```

The installer picks the archive for your machine, checks it against the
release's `SHA256SUMS`, unpacks it into `~/.loup`
(`%LOCALAPPDATA%\Programs\Loup` on Windows) and puts its `bin` directory on
your `PATH`; it needs no administrator rights. You get `loup`, the Stage0
compiler `loup-bootstrap` and the Wasm runtime `loup-launcher`. Open a new
shell and check:

```sh
loup --version             # loup 1.26.0 or later
```

CI installs the exact version it tests with, 1.26.0. To do the same:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/download/v1.26.0/loup-install.sh | sh -s -- --version 1.26.0
```

To install by hand, download your platform's archive from the
[releases page](https://github.com/code-craft-ai-company/loup-releases/releases),
check it against `SHA256SUMS`, unpack it anywhere and add its `bin` directory to
`PATH`. The [loup-releases README](https://github.com/code-craft-ai-company/loup-releases#verify-a-download)
explains how to verify the Sigstore signature on `SHA256SUMS`.

Loup Lite leaves out Loup's cryptography library and the full set of Loup
packages; this example needs neither. Commercial use of Loup needs a
license: <https://code-craft.ai/loup/license>.

## Usage

```sh
make run ARGS="-r summary tests/fixtures/access.log"   # loup run bin/logwatch.lpscr -- ARGS
make -s gen ARGS="-n 5000" > sample.log                # a synthetic log
make ci                                                # check, unit tests, end-to-end tests
```

The scripts are executable (`#!/usr/bin/env -S loup run`). `bin/loggen.lpscr`
writes a deterministic day of traffic with an outage at 14:00:

```text
$ loup run bin/loggen.lpscr -n 3 -s 2
203.0.113.178 - - [10/Oct/2026:08:32:23 +0000] "GET /index.html HTTP/1.1" 200 6013 "-" "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
192.0.2.24 - - [10/Oct/2026:16:04:55 +0000] "GET /api/items HTTP/1.1" 200 2819 "-" "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
192.0.2.24 - - [10/Oct/2026:20:04:42 +0000] "GET /static/site.css HTTP/1.1" 200 61265 "-" "curl/8.9.1"
$ loup run bin/loggen.lpscr -n 2000 > sample.log
$ ./bin/logwatch.lpscr -r summary,paths,bursts -n 5 sample.log
Summary
  files      1
  lines      2000
  requests   2000
  malformed  0
  combined   2000
  first      10/Oct/2026:00:08:27 +0000
  last       10/Oct/2026:23:58:52 +0000
  bytes      25508007
  clients    30
  paths      12
  4xx        65
  5xx        163

Top paths (5 of 12)
  rank  path              requests  percent     bytes  4xx  5xx
     1  /                      341    17.1%   2147885    0    1
     2  /api/items             297    14.9%    591963    0   53
     3  /static/site.css       279    14.0%   9470585    0    2
     4  /static/app.js         277    13.9%  10252541    0    2
     5  /api/items/42          205    10.3%    342377    0   53

Error bursts (5+ 5xx a minute)
  start             end               minutes  errors  requests  top_path
  2026-10-10 14:00  2026-10-10 14:04        5     155       210  /api/items/42
```

[`tests/fixtures/access.log`](tests/fixtures/access.log) mixes both formats
and has two malformed lines; [`tests/expected/`](tests/expected/) holds its
complete reports in all three formats.

```text
$ loup run bin/logwatch.lpscr -- --report=status --format=csv tests/fixtures/access.log
report,status,requests,percent
status,2xx,9,31.0
status,200,8,27.6
status,201,1,3.4
status,3xx,1,3.4
status,304,1,3.4
status,4xx,4,13.8
status,403,1,3.4
...
logwatch: skipped 2 malformed line(s) (--strict lists them)
$ ./bin/logwatch.lpscr -r bursts -t 3 -f json tests/fixtures/access.log
{
  "bursts": [
    {
      "start": "2026-10-10 14:00",
      "end": "2026-10-10 14:01",
      "minutes": 2,
      "errors": 10,
      "requests": 11,
      "top_path": "/api/items"
    },
    {
      "start": "2026-10-10 14:03",
      "end": "2026-10-10 14:03",
      "minutes": 1,
      "errors": 3,
      "requests": 3,
      "top_path": "/api/items"
    }
  ]
}
logwatch: skipped 2 malformed line(s) (--strict lists them)
$ ./bin/logwatch.lpscr -s -r hourly tests/fixtures/access.log | sed -n 10,18p; echo "status ${PIPESTATUS[0]}"
logwatch: tests/fixtures/access.log:12: missing [timestamp]
logwatch: tests/fixtures/access.log:31: bad timestamp '10/Oct/2026:31:04:00 +0200'
     7         0     0.0%    0    0
     8         0     0.0%    0    0
     9         3    10.3%    0    0 ########
    10         4    13.8%    2    0 ##########
    11         3    10.3%    1    0 ########
    12         0     0.0%    0    0
    13         1     3.4%    0    0 ###
    14        17    58.6%    1   15 ########################################
    15         0     0.0%    0    0
status 1
```

### Options

| Option | Meaning |
|---|---|
| `-f`, `--format FORMAT` | `text` (default), `csv` or `json` |
| `-r`, `--report NAMES` | comma-separated reports, printed in the order given (default all): `summary`, `paths`, `status`, `hourly`, `clients`, `bursts`, or `all` |
| `-n`, `--top N` | rows in the `paths` and `clients` reports (default 10) |
| `-t`, `--burst-threshold N` | errors a minute that make a minute part of a burst (default 5) |
| `-4`, `--include-4xx` | count 4xx as well as 5xx responses as errors in `bursts` |
| `-s`, `--strict` | list every malformed line as `FILE:LINE: reason` and exit 1 |
| `-h`, `--help` / `-V`, `--version` | help text / `logwatch (loup-cmd-logwatch) 0.1.0` |

With no FILE, or with `-`, logwatch reads standard input. Short options can
be combined (`-s4`) and take attached values (`-fjson`, `-n5`).

**Long options need `--` under `loup run`.** `loup run SCRIPT ARGS` treats
words starting with `--` as its own flags, and the self-hosted `loup run` on
Linux x86-64 drops unknown ones silently. Write
`loup run bin/logwatch.lpscr -- --format json FILE` (or
`./bin/logwatch.lpscr -- --format json FILE`), or use the short options,
which pass through unchanged. `make run` adds the `--` for you.

Reports: **summary** (files, lines, requests, malformed and Combined-format
lines, first and last time as written, bytes, distinct clients and paths,
4xx and 5xx counts); **paths** and **clients** (requests, share, bytes, 4xx,
5xx; ties in name order; paths without their query string); **status**
(each class, then its codes); **hourly** (all 24 hours of the day, with a
bar in text output); **bursts** (runs of consecutive minutes that each have
at least `-t` errors, with the path that failed most).

Exit status: `0` success, `1` an input could not be read or `--strict` found
malformed lines, `2` usage error.

## What this example shows

- **Scripts that import dual-mode modules.** `bin/logwatch.lpscr` and
  `bin/loggen.lpscr` are `host.scripted` programs: top-level statements that
  read arguments and files, print, and call `exit(n)`. Everything they share
  (the log format, counting, report tables, text and CSV output) is
  `host.dual` code in `lib/*.loup`, which unit tests import directly.
  host.dual keeps that code typed; several modules also use features only
  the interpreters have (generators, template fences, list `map`, `filter`
  and `reduce`, spread), so they are not compiled.
- **Relative imports across directories.** A script's package root is its
  own directory, so `bin/` scripts import `from ..lib.clf import (...)`,
  `lib/` modules import each other with `from .clf import (...)`, and tests
  use `from ..lib...` too. No `LOUPPATH` is needed, and the scripts run from
  any working directory.
- **Choosing a mode per module.** `lib/render_json.lpscr` is the one
  `host.scripted` lib module: a JSON document is built from `Any` values,
  which `host.dual` accepts but flags with a `W_ANY_IN_AOT_MODE` warning on
  every run.
- **`system.regex` with named groups**, on the parts of a line that have a
  grammar (the timestamp and the request line), while plain string searches
  cut the line into fields. The regex engine is written in Loup, so the
  parser class remembers every distinct timestamp and request it matched.
- **Report data separate from presentation.** Reports are tables of typed
  cells (an `enum Cell { Text, Count, Tenths }`), rendered by three classes
  that implement an `interface TableFormat`: text and CSV write one table
  at a time and share the interface's default `render()`, JSON overrides
  it. Percentages are integer tenths, so there is no float formatting.
- **Language features where the code needs them:** a `gen func` that
  yields `(number, line)` tuples to a destructuring `for`; a generic
  `ascending[T]` with a `where T: Comparable[T]` bound that sorts names and
  status codes alike; property getters (`Stats.client_errors`); struct
  copies with `with (...)`; `match` arms with guards (loggen's status
  rules); `T?` return types; a generic type alias; list spread and
  `map`/`filter`/`reduce`; `!` on regex groups the pattern guarantees; a
  local `const`; a `(text)` template fence for `--help` and a `"""` string
  for loggen's; and `catch (IoError)` without a binding.
- **`data.csv` and `system.json`** for output, **`core.random`** for a
  deterministic generator, **`core.datetime`**'s day count for minute
  keys, **`io.proc`** to ask `test -r`, and **classes with `modifier`
  methods** called inside `safe { }`.
- **Testing a script project.** `make check` type-checks each entry script
  with `loup-bootstrap check FILE`; unit tests are `tests/*_test.lpscr`;
  `tests/e2e.sh` runs the scripts with `loup run` against expected output.

## Limitations

- Speed: about 1,000 lines a second under `loup run` (5,000 generated lines
  in 4.6 s), mostly the pure-Loup regex engine. Real logs repeat timestamps
  and requests, which the parser's memo tables make cheap.
- Input is read whole, not streamed (Loup 1.26 has no line reader for
  standard input), and there is no follow mode.
- Times are used as written: the zone offset is shown but not applied, so a
  log is assumed to use one zone.
- A file without read permission is reported (`logwatch: FILE: Permission
  denied`, status 1) and skipped, like a missing one. The self-hosted
  `loup run` cannot catch `IoError` and `io.fs` has no permission test, so
  logwatch asks `test -r` first. That interpreter hands each argument of a
  process to `sh` inside double quotes, so a name holding `$`, a backquote,
  `"` or `\` is not checked: if such a file cannot be read, `loup run`
  still ends with `IoError`. Stage0 (`loup-bootstrap run`, and `loup` on
  macOS, Windows and Linux arm64) catches it: `logwatch: FILE: cannot be
  read`.

## Layout

```text
bin/logwatch.lpscr          # the analyser (host.scripted entry script)
bin/loggen.lpscr            # the sample log generator (host.scripted)
lib/appinfo.loup            # name, version, exit statuses
lib/args.loup               # option parsing
lib/usage.loup              # --help and --version text (a template fence)
lib/inputs.loup             # input checks: missing, directory, unreadable
lib/clf.loup                # log line parser (system.regex), Entry, format_entry
lib/stats.loup              # counters
lib/analyse.loup            # log_lines generator; feeds each line through the parser into the counters
lib/reports.loup            # report tables
lib/render.loup             # interface TableFormat; text and CSV output
lib/render_json.lpscr       # JsonFormat (host.scripted: uses Any)
lib/sample.loup             # the generator behind loggen
tests/*_test.lpscr          # unit tests (make test)
tests/e2e.sh                # end-to-end tests with loup run (make e2e)
tests/fixtures/access.log   # sample log with edge cases
tests/expected/             # its full reports in text, CSV and JSON
specs/logwatch/             # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every check and test command and the conventions
for changing the code.

## License

[MIT](LICENSE), copyright 2026 Code Craft AI LLC. The Loup skill in
[`skills/loup-programmer/`](skills/loup-programmer/) is copied from the Loup
project and is not covered by this license; it keeps the Loup project's terms.
