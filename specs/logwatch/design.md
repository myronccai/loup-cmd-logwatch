# Design: logwatch

## Overview

`bin/logwatch.lpscr` is a `host.scripted` script. Its top-level statements
parse `args()` into `Options`, handle `--help` and `--version`, read each
input whole, feed it to an `Analyser`, build the requested report tables,
print them in the chosen format and `exit` with the status. Everything else
is in `lib/`: `host.dual` modules of pure functions and small classes, which
the unit tests import directly.

`bin/loggen.lpscr` is a second thin script over the same modules: it parses
its options with `parse_gen_args` and prints `generate(...)`.

```text
args() ─ parse_args ─► Options
files ─ readText ─► Analyser.feed ─ ClfParser.parse ─► Entry ─► Stats.add
Stats ─ build_reports ─► list[Table] ─ render_text / render_csv / render_json ─► stdout
```

## Modules

| Module | Mode | Contents |
|---|---|---|
| `bin/logwatch.lpscr` | scripted | top level: options, input checks, output, exit status |
| `bin/loggen.lpscr` | scripted | top level of the generator |
| `lib/appinfo.loup` | dual | name, version, exit statuses |
| `lib/args.loup` | dual | `Options`, `parse_args`, `parse_reports`, `parse_positive` |
| `lib/usage.loup` | dual | `usage()`, `version_line()` |
| `lib/clf.loup` | dual | `Stamp`, `Request`, `Entry`, `ClfParser`, `path_of`, `closing_quote`, `unescape`, `escape`, date arithmetic, `make_stamp`, `format_entry` |
| `lib/stats.loup` | dual | `Tally`, `Minute`, `Stats` |
| `lib/analyse.loup` | dual | `Analyser`: splits text into lines, parses, counts, records problems |
| `lib/reports.loup` | dual | `Cell`, `Table`, `percent_tenths`, `top_keys`, one function per report, `build_reports` |
| `lib/render.loup` | dual | `render_text`, `render_csv` (`data.csv`) |
| `lib/render_json.lpscr` | scripted | `render_json` (`system.json`) |
| `lib/sample.loup` | dual | `generate`, `parse_gen_args` |

### Parsing

A line is cut with `index_of` and `slice`: HOST and IDENT end at a space,
USER at ` [`, the timestamp at `]`, the request at the first unescaped `"`
(`closing_quote` counts the backslashes before a quote), then STATUS and
BYTES, then optionally two more quoted fields. `system.regex` then matches
the timestamp (`(?P<day>\d{2})/(?P<month>[A-Z][a-z]{2})/...`) and the request
line (`(?P<method>[A-Z]+) (?P<target>\S+)(?: (?P<protocol>HTTP/...))?`).

The 1.26 regex engine is pure Loup and allocates a table of
`instructions × input length` per match: about 4 ms for a whole Combined
line under `loup run`, against about 0.6 ms for each of the two short
fields. `ClfParser` therefore keeps two memo tables, timestamp text → `Stamp`
and request text → `Request`; logs repeat both. Its methods are `modifier`
and callers use `safe { }`.

### Counting

`Stats` holds per-path and per-client `Tally` values (requests, bytes, 4xx,
5xx), a status → count map, 24 hourly tallies, and per-minute `Minute`
values keyed by minutes since 1970 (`days_from_civil` × 1440 + hour × 60 +
minute, on the time as written). A minute counts its requests, its errors
(status ≥ `error_min`: 500, or 400 with `--include-4xx`) and its errors per
path. First and last are chosen by time, not position.

### Reports

Each report is a `Table`: a name, a title, column names and rows of
`Cell` values (`Text`, `Count`, or `Tenths`, a one-decimal number times
ten). Percentages are `(part × 2000 + whole) / (2 × whole)` tenths, which
rounds half up with integers only. Bursts are found in one pass over the
sorted minute keys: a run continues while each next key is the previous
plus one and has at least the threshold of errors.

### Output

- Text: the title, a header (not for the keyed summary), and columns padded
  to their widest cell, numbers right-aligned; the hourly table appends a
  bar of up to 40 `#`. `(none)` stands for an empty table.
- CSV: `data.csv.write` of a header row and the rows, each prefixed with the
  report name; tables separated by a blank line.
- JSON: built from `dict[string, Any]` and `list[Any]` and written with
  `stringifyIndented(doc, 2)`. This module is `host.scripted` because `Any`
  in a `host.dual` module triggers `W_ANY_IN_AOT_MODE` on every run.

### Generator

`sample.generate` uses `core.random.Random(seed)` through a small `Dice`
class that takes the generator's high bits (the low bits of its LCG repeat
with a short period). It picks an hour by weight, a target by weight, a
client (40% from four heavy clients), status and size by path, and makes a
tenth of the lines an outage between 14:00 and 14:05 with 80% `503`. Entries
are sorted by time and written with `format_entry`.

## What this example shows

- The "scripts import dual modules" layout: thin `host.scripted` entry
  scripts, testable `host.dual` modules, one scripted module where `Any` is
  natural.
- Relative imports from `bin/` and `tests/` into `lib/` (a script's package
  root is its own directory).
- `system.regex` named groups, memoised; `data.csv`, `system.json`,
  `core.random`, `core.string_utils`, `system.text`.
- Typed report cells with a payload `enum`, and integer-only percentages.

## Error handling

- Usage errors (`parse_args` returns `Err`): message and the `Try` line on
  standard error, status 2, no output.
- Inputs: the script checks `exists` and `isDir` before `readText`, because
  the self-hosted `loup run` cannot catch `IoError`. A missing file or a
  directory gives `logwatch: FILE: No such file or directory` / `Is a
  directory`, status 1, and the remaining inputs are still read. A file that
  exists but cannot be read ends the run with an uncaught `IoError`
  (status 1).
- Malformed lines are counted; their `FILE:LINE: reason` are kept in
  `Analyser.problems` and printed with `--strict` (status 1), otherwise
  summarised in one line on standard error.

## Testing

- `tests/clf_test.lpscr`: fields of both formats, escaped quotes, `-`
  requests, trailing fields, every malformed-line reason, memoisation,
  `path_of`, `closing_quote`, `unescape`, date arithmetic, `format_entry`
  round trip.
- `tests/analyse_test.lpscr`: counters, tallies, first/last by time, blank
  lines, CRLF, problem locations, `error_min`.
- `tests/reports_test.lpscr`: rounding, ordering, every report on the
  fixture, burst thresholds with and without 4xx, report order.
- `tests/render_test.lpscr`: text alignment, bars, keyed and empty tables,
  CSV quoting, exact JSON text.
- `tests/args_test.lpscr`: short clusters, attached values, long options with
  `=`, options after files, `--`, every usage error.
- `tests/sample_test.lpscr`: determinism, parseability, time order, Common
  format, the outage burst, generator options.
- `tests/e2e.sh`: runs both scripts with `loup run`; compares full reports
  with `tests/expected/`, single reports, standard input, CRLF, every error
  message and exit status, and the generator's exact output.
