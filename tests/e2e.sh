#!/usr/bin/env bash
# End-to-end tests: run the scripts with `loup run` and compare their
# standard output (byte for byte), standard error where it matters, and exit
# status with the expected ones.
#
# usage: tests/e2e.sh [LOUP]     (run from the repository root)
# One case runs the script under Stage0 instead: $LOUP_BOOTSTRAP (default
# loup-bootstrap).

set -u
LOUP=${1:-loup}
LOUP_BOOTSTRAP=${LOUP_BOOTSTRAP:-loup-bootstrap}
SCRIPT=bin/logwatch.lpscr
LOG=tests/fixtures/access.log
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# run ARGS...: the script under test, with ARGS after `--` so that long
# options reach it, standard input from the file named by $IN (default
# /dev/null), output to $TMP/out and $TMP/err. Returns its exit status.
run() {
    "$LOUP" run "$SCRIPT" -- "$@" < "${IN:-/dev/null}" > "$TMP/out" 2> "$TMP/err"
}

report() {
    local name=$1 status=$2 want_status=$3 want_file=$4 got_file=$5
    if [ "$status" -eq "$want_status" ] && cmp -s "$want_file" "$got_file"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $name (exit $status, expected $want_status)"
        diff "$want_file" "$got_file" | sed 's/^/    /' | head -20
        sed 's/^/    stderr: /' "$TMP/err" | head -5
    fi
}

# check_file NAME STATUS EXPECTED_FILE [ARGS...]: compare standard output.
check_file() {
    local name=$1 want_status=$2 want_file=$3
    shift 3
    run "$@"
    report "$name" $? "$want_status" "$want_file" "$TMP/out"
}

# check NAME STATUS EXPECTED_STDOUT [ARGS...]
check() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    check_file "$name" "$want_status" "$TMP/want" "$@"
}

# check_grep NAME STATUS REGEX EXPECTED [ARGS...]: compare the lines of
# standard output that match REGEX.
check_grep() {
    local name=$1 want_status=$2 regex=$3
    printf '%s' "$4" > "$TMP/want"
    shift 4
    run "$@"
    local status=$?
    grep -E "$regex" "$TMP/out" > "$TMP/got"
    report "$name" $status "$want_status" "$TMP/want" "$TMP/got"
}

# check_err NAME STATUS EXPECTED_STDERR [ARGS...]: compare standard error.
check_err() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    run "$@"
    report "$name" $? "$want_status" "$TMP/want" "$TMP/err"
}

# --- full reports (expected files reviewed by hand) ---------------------

check_file "text report"   0 tests/expected/access.txt  "$LOG"
check_file "csv report"    0 tests/expected/access.csv  -f csv "$LOG"
check_file "json report"   0 tests/expected/access.json --format=json "$LOG"

# --- single reports and options -----------------------------------------

check "summary" 0 'Summary
  files      1
  lines      31
  requests   29
  malformed  2
  combined   25
  first      10/Oct/2026:09:58:01 +0200
  last       10/Oct/2026:16:45:00 +0200
  bytes      49099
  clients    5
  paths      12
  4xx        4
  5xx        15
' -r summary "$LOG"

check "top 3 paths" 0 'Top paths (3 of 12)
  rank  path           requests  percent  bytes  4xx  5xx
     1  /api/items           11    37.9%   4096    0    9
     2  /api/items/42         5    17.2%      0    0    5
     3  /                     2     6.9%  10240    0    0
' -r paths -n3 "$LOG"

check "clients json" 0 '{
  "clients": [
    {
      "rank": 1,
      "client": "192.0.2.44",
      "requests": 10,
      "percent": 34.5,
      "bytes": 2048,
      "4xx": 0,
      "5xx": 9
    }
  ]
}
' --report clients --top 1 -f json "$LOG"

check "reports in order given" 0 'report,start,end,minutes,errors,requests,top_path
bursts,2026-10-10 14:00,2026-10-10 14:01,2,10,11,/api/items

report,status,requests,percent
status,2xx,9,31.0
status,200,8,27.6
status,201,1,3.4
status,3xx,1,3.4
status,304,1,3.4
status,4xx,4,13.8
status,403,1,3.4
status,404,2,6.9
status,408,1,3.4
status,5xx,15,51.7
status,500,1,3.4
status,502,3,10.3
status,503,11,37.9
' -fcsv -r bursts,status,bursts "$LOG"

check "bursts threshold 3" 0 'report,start,end,minutes,errors,requests,top_path
bursts,2026-10-10 14:00,2026-10-10 14:01,2,10,11,/api/items
bursts,2026-10-10 14:03,2026-10-10 14:03,1,3,3,/api/items
' -f csv -r bursts -t 3 "$LOG"

check "bursts threshold 2" 0 'report,start,end,minutes,errors,requests,top_path
bursts,2026-10-10 14:00,2026-10-10 14:03,4,15,17,/api/items
' -f csv -r bursts --burst-threshold=2 "$LOG"

check "bursts with 4xx" 0 'Error bursts (3+ 4xx/5xx a minute)
  start             end               minutes  errors  requests  top_path
  2026-10-10 14:00  2026-10-10 14:03        4      16        17  /api/items
' -r bursts -t3 -4 "$LOG"

check "no bursts" 0 'Error bursts (6+ 5xx a minute)
  (none)
' -r bursts -t 6 "$LOG"

# --- input ------------------------------------------------------------------

SUMMARY_FILES='^summary,(files|lines|requests),'

IN=$LOG check_grep "standard input"   0 "$SUMMARY_FILES" $'summary,files,1\nsummary,lines,31\nsummary,requests,29\n' -r summary -f csv
IN=$LOG check_grep "dash is stdin"    0 "$SUMMARY_FILES" $'summary,files,2\nsummary,lines,62\nsummary,requests,58\n' -r summary -f csv - "$LOG"
check_grep "empty input"              0 "$SUMMARY_FILES" $'summary,files,1\nsummary,lines,0\nsummary,requests,0\n' -r summary -f csv /dev/null
printf '%s' "$(head -3 "$LOG")" | tr '\n' '\r' | sed 's/\r/\r\n/g' > "$TMP/crlf.log"
check_grep "CRLF, no final newline" 0 "$SUMMARY_FILES" $'summary,files,1\nsummary,lines,3\nsummary,requests,3\n' -r summary -f csv "$TMP/crlf.log"

# --- errors and exit statuses -------------------------------------------------

check_err "malformed notice"   0 $'logwatch: skipped 2 malformed line(s) (--strict lists them)\n' -r summary "$LOG"
check_err "strict"             1 "logwatch: $LOG:12: missing [timestamp]
logwatch: $LOG:31: bad timestamp '10/Oct/2026:31:04:00 +0200'
" -s -r summary "$LOG"
check_err "missing file"       1 $'logwatch: nope.log: No such file or directory\n' nope.log
check "missing file, no report" 1 '' nope.log
check_err "directory"          1 $'logwatch: tests: Is a directory\n' tests
check_grep "missing and present" 1 "$SUMMARY_FILES" $'summary,files,1\nsummary,lines,31\nsummary,requests,29\n' -r summary -f csv nope.log "$LOG"

# A file without read permission is reported like a missing one (root can
# read anything, so these cases need another user). Under `loup run` the
# check is test(1); a name with `$` skips that check, and only Stage0 can
# then catch the IoError of the read.
if [ "$(id -u)" -ne 0 ]; then
    cp "$LOG" "$TMP/locked.log"
    cp "$LOG" "$TMP/we\$ird.log"
    chmod 000 "$TMP/locked.log" "$TMP/we\$ird.log"
    check_err "unreadable file" 1 "logwatch: $TMP/locked.log: Permission denied
" -r summary "$TMP/locked.log"
    check_grep "unreadable and present" 1 "$SUMMARY_FILES" $'summary,files,1\nsummary,lines,31\nsummary,requests,29\n' -r summary -f csv "$TMP/locked.log" "$LOG"
    SAVED=$LOUP
    LOUP=$LOUP_BOOTSTRAP
    check_err "unreadable, caught by Stage0" 1 "logwatch: $TMP/we\$ird.log: cannot be read
" -r summary "$TMP/we\$ird.log"
    LOUP=$SAVED
else
    echo "e2e: running as root, unreadable-file cases skipped"
fi

USAGE_HINT="Try 'logwatch --help' for more information."
check_err "unknown long option" 2 "logwatch: unrecognized option '--bogus'
$USAGE_HINT
" --bogus
check_err "unknown short option" 2 "logwatch: invalid option -- 'x'
$USAGE_HINT
" -x
check_err "missing value"      2 "logwatch: option requires an argument -- 'f'
$USAGE_HINT
" -f
check_err "bad format"         2 "logwatch: invalid format 'xml' (choose text, csv or json)
$USAGE_HINT
" -f xml
check_err "bad report"         2 "logwatch: invalid report 'top' (choose from summary, paths, status, hourly, clients, bursts, all)
$USAGE_HINT
" -r top
check_err "bad top"            2 "logwatch: invalid --top value '0'
$USAGE_HINT
" -n 0
check "usage error, no output" 2 '' -n 0 "$LOG"

check "version" 0 $'logwatch (loup-cmd-logwatch) 0.1.0\n' --version
check_grep "help" 0 '^usage:' $'usage: logwatch [OPTION]... [FILE]...\n' -h

# --- loggen ---------------------------------------------------------------------

SCRIPT=bin/loggen.lpscr
check "loggen common" 0 '192.0.2.38 - - [10/Oct/2026:05:25:16 +0000] "GET /api/orders HTTP/1.1" 200 3808
192.0.2.10 - - [10/Oct/2026:13:47:07 +0000] "GET /static/site.css HTTP/1.1" 200 59872
192.0.2.17 - - [10/Oct/2026:14:22:33 +0000] "POST /login HTTP/1.1" 200 7746
198.51.100.94 - - [10/Oct/2026:17:59:28 +0000] "GET / HTTP/1.1" 200 8786
192.0.2.45 - - [10/Oct/2026:18:53:22 +0000] "GET /static/site.css HTTP/1.1" 200 73332
' -n 5 -s 1 -c
check "loggen nothing" 0 '' -n 0
check "loggen version" 0 $'loggen (loup-cmd-logwatch) 0.1.0\n' -V
check_err "loggen bad option" 2 $'loggen: unrecognized argument \'-x\'\nusage: loggen [-n LINES] [-s SEED] [-c]\n\nWrite LINES (default 1000) access log lines for one day in Combined Log\nFormat, or Common Log Format with -c. The same SEED (default 1) gives the\nsame log.\n' -x

"$LOUP" run bin/loggen.lpscr -- -n 300 -s 1 > "$TMP/gen.log"
SCRIPT=bin/logwatch.lpscr
check "loggen into logwatch" 0 'report,field,value
summary,files,1
summary,lines,300
summary,requests,300
summary,malformed,0
summary,combined,300
summary,first,10/Oct/2026:00:05:46 +0000
summary,last,10/Oct/2026:23:48:13 +0000
summary,bytes,3089842
summary,clients,30
summary,paths,11
summary,4xx,10
summary,5xx,24

report,start,end,minutes,errors,requests,top_path
bursts,2026-10-10 14:02,2026-10-10 14:04,3,18,23,/api/items/42
' -r summary,bursts -f csv "$TMP/gen.log"

echo "e2e: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
