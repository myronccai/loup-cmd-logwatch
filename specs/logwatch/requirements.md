# Requirements: logwatch

## Introduction

`logwatch` reads web server access logs in the Common Log Format (CLF) or the
Combined Log Format and prints reports about them: a summary, the most
requested paths, the status code mix, an hourly histogram, the busiest
clients and bursts of errors. Reports are written as aligned text, CSV or
JSON.

It is the first host-scripted project of the loup-cmd series. The program is
a `host.scripted` entry script in `bin/` that imports shared `host.dual`
modules from `lib/`; a second script, `bin/loggen.lpscr`, writes synthetic
logs with the same modules.

## Requirements

### Requirement 1: Input

**User Story:** As an operator, I want to point logwatch at one or more log
files, or pipe a log into it, so that I can analyse logs wherever they are.

#### Acceptance Criteria

1. WHEN logwatch is run with FILE operands, THE program SHALL read each file
   in order and analyse all their lines together.
2. WHEN no FILE is given, or a FILE is `-`, THE program SHALL read standard
   input.
3. WHEN a FILE cannot be read, THE program SHALL print
   `logwatch: FILE: REASON` on standard error, continue with the remaining
   files, and exit with status 1.
4. WHEN no input could be read at all, THE program SHALL print no report.
5. THE program SHALL ignore empty lines and a trailing carriage return on
   each line.

### Requirement 2: Parsing

**User Story:** As an operator, I want both common log formats understood so
that logs from Apache, nginx and similar servers can be analysed unchanged.

#### Acceptance Criteria

1. THE parser SHALL accept `HOST IDENT USER [DD/Mon/YYYY:HH:MM:SS +ZZZZ]
   "REQUEST" STATUS BYTES` (Common) and the same followed by `"REFERER"
   "USER-AGENT"` (Combined); further trailing fields SHALL be ignored.
2. THE parser SHALL use `system.regex` to validate and split the timestamp
   and the request line (`METHOD TARGET [PROTOCOL]`).
3. WHEN a quoted field contains a backslash-escaped quote (`\"`), THE parser
   SHALL keep it inside the field.
4. WHEN the request line is not `METHOD TARGET [PROTOCOL]` (for example
   `-`), THE parser SHALL keep the entry and count it under the path `-`.
5. THE path of a request SHALL be its target without the query string or
   fragment.
6. WHEN BYTES is `-`, THE parser SHALL count zero bytes.
7. WHEN a line does not have the structure of 2.1, a valid timestamp, a
   status from 100 to 599 or a numeric byte count, THE parser SHALL reject it
   with a reason, and THE program SHALL count it as malformed.
8. WHEN malformed lines were found, THE program SHALL print
   `logwatch: skipped N malformed line(s) (--strict lists them)` on standard
   error; WHEN `-s`/`--strict` is given it SHALL instead print
   `logwatch: FILE:LINE: REASON` for each one and exit with status 1.

### Requirement 3: Reports

**User Story:** As an operator, I want the usual traffic questions answered
at a glance so that I can spot problems quickly.

#### Acceptance Criteria

1. THE `summary` report SHALL give the number of files, non-empty lines,
   parsed requests, malformed lines, Combined-format lines, the first and
   last timestamp (as written in the log), total bytes, distinct clients,
   distinct paths, and the 4xx and 5xx response counts.
2. THE `paths` report SHALL list the N most requested paths (`-n`, default
   10) with requests, percentage of all requests, bytes, 4xx and 5xx counts,
   ordered by requests, then by path.
3. THE `status` report SHALL list each status class (`2xx`, ...) followed by
   its status codes, with counts and percentages, in ascending order.
4. THE `hourly` report SHALL list all 24 hours of the day with requests,
   percentage, 4xx and 5xx counts, using the time as written in the log;
   the text output SHALL add a bar scaled to the busiest hour.
5. THE `clients` report SHALL list the N busiest client hosts in the same
   shape as the `paths` report.
6. THE `bursts` report SHALL list every run of consecutive minutes in which
   each minute has at least T error responses (`-t`, default 5), with its
   first and last minute, length in minutes, errors, requests, and the path
   with the most errors in the run. Errors are 5xx responses, or 4xx and
   5xx with `-4`/`--include-4xx`.
7. WHEN `-r`/`--report` is given a comma-separated list of report names (or
   `all`), THE program SHALL print only those reports, in the order given,
   each once; the default is all six.
8. THE program SHALL compute percentages to one decimal place, rounding
   halves up.

### Requirement 4: Output formats

**User Story:** As a script author, I want machine-readable output so that I
can feed the reports to other tools.

#### Acceptance Criteria

1. WHEN `-f text` (the default) is given, THE program SHALL print each report
   under its title as aligned columns, numbers right-aligned, with a blank
   line between reports and `(none)` for an empty report.
2. WHEN `-f csv` is given, THE program SHALL print each report as a CSV
   table (written with `data.csv`) whose first column is the report name,
   with a header row, and a blank line between tables.
3. WHEN `-f json` is given, THE program SHALL print one JSON object (written
   with `system.json`) with a member per report: the summary as an object,
   the other reports as arrays of objects; counts SHALL be JSON integers and
   percentages JSON numbers.

### Requirement 5: Command line

**User Story:** As a shell user, I want conventional options and statuses so
that logwatch fits into scripts.

#### Acceptance Criteria

1. THE program SHALL accept `-f/--format`, `-r/--report`, `-n/--top`,
   `-t/--burst-threshold`, `-4/--include-4xx`, `-s/--strict`, `-h/--help`
   and `-V/--version`; value options SHALL accept `-fVALUE`, `-f VALUE`,
   `--format VALUE` and `--format=VALUE`; `--` SHALL end the options.
2. WHEN an option is unknown, lacks its value, or has an invalid value (an
   unknown format or report, a count below 1), THE program SHALL print
   `logwatch: MESSAGE` and `Try 'logwatch --help' for more information.` on
   standard error and exit with status 2.
3. WHEN `--version` is given, THE program SHALL print
   `logwatch (loup-cmd-logwatch) 0.1.0`.
4. THE program SHALL exit with status 0 on success, 1 when an input could not
   be read or `--strict` found malformed lines, and 2 on a usage error.

### Requirement 6: Sample logs

**User Story:** As a developer, I want to generate realistic logs so that I
can try logwatch and measure it without real traffic.

#### Acceptance Criteria

1. WHEN `bin/loggen.lpscr` is run, THE generator SHALL write N log lines
   (`-n`, default 1000) spread over one day in time order, in the Combined
   format or, with `-c`/`--common`, the Common format.
2. THE generator SHALL be deterministic for a given seed (`-s`, default 1)
   and SHALL include an outage between 14:00 and 14:05 in which most `/api/`
   requests fail with 503.
3. THE lines the generator writes SHALL be accepted by the logwatch parser.
