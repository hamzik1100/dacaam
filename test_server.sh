#!/usr/bin/env bash
#
# Runs every PHP suite — the API and the Super Admin dashboard.
#
#   bash test_server.sh
#
# Two things here are not optional, and both were learned the hard way.
#
# First, each suite gets its own freshly seeded database. The auth suite locks
# accounts and changes passwords on purpose and does not undo them, so a later
# suite signing in as those users fails for reasons that have nothing to do with
# the code under test. Chasing that costs an hour every time.
#
# Second, the servers start with the restrictions the real host imposes:
# exec and friends disabled, errors written to a log file. Shared hosting
# disables shelling out, so a controller that shells out passes on this machine
# and dies on the server — that shipped once. And a fatal thrown after the page
# has been echoed leaves a 200 with a complete body, invisible to any check that
# only reads the response; the log is the only place it appears.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PHP="${PHP:-/d/xampp/php/php.exe}"
API_PORT=8090
ADMIN_PORT=8091
LOG="$ROOT/backend/storage/logs/error.log"

# Matches Hostinger, where these sit in disable_functions.
BLOCKED="exec,shell_exec,passthru,system,proc_open"

if [ ! -x "$PHP" ] && ! command -v "$PHP" > /dev/null 2>&1; then
    echo "PHP lama helin: $PHP" >&2
    echo "Ku bilow:  PHP=/path/to/php.exe bash test_server.sh" >&2
    exit 1
fi

mkdir -p "$(dirname "$LOG")"

# ---------------------------------------------------------------- servers

started=()

stop_servers() {
    for port in "$API_PORT" "$ADMIN_PORT"; do
        for pid in $(netstat -ano 2>/dev/null | grep ":$port " | grep LISTENING | awk '{print $5}' | sort -u); do
            taskkill //F //PID "$pid" > /dev/null 2>&1
        done
    done
}

trap stop_servers EXIT

start_server() {
    local name="$1" dir="$2" port="$3"

    # proc_open stays enabled for the API: nothing in it shells out, and the
    # backup falls back to a pure-PHP dump when it cannot. The admin gets the
    # full set because that is where the button lives.
    # -t matters: without a document root the front controller resolves its
    # paths against whatever directory this script was run from, and every
    # request 404s while the port still answers.
    "$PHP" -d disable_functions="$BLOCKED" \
           -d error_log="$LOG" -d log_errors=1 -d display_errors=0 \
           -S "127.0.0.1:$port" -t "$dir" "$dir/index.php" > /dev/null 2>&1 &

    started+=("$!")

    for _ in $(seq 1 20); do
        if [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/" || true)" != "000" ]; then
            echo "     $name -> 127.0.0.1:$port"
            return 0
        fi
        sleep 0.3
    done

    echo "     FAIL: $name ma bilaaban ($port)" >&2
    return 1
}

reseed() {
    (
        cd "$ROOT/backend" || exit 1
        "$PHP" bin/migrate.php --fresh --seed > /dev/null 2>&1 || exit 1

        # The same chain deploy.sh runs, in the same order. A suite passing on a
        # schema the server will never have is worth nothing.
        for step in upgrade_payment_methods upgrade_draft_cancel \
                    upgrade_customer_orders upgrade_payment_status \
                    upgrade_notifications upgrade_request_keys \
                    upgrade_alerts upgrade_expense_cancel \
                    upgrade_shifts upgrade_shift_counts upgrade_refund_rows \
                    upgrade_admin_security upgrade_platform_billing; do
            "$PHP" "bin/$step.php" > /dev/null 2>&1
        done
    )
}

# ------------------------------------------------------------------- run

echo
echo "1/3  Serverrada la bilaabayo..."

stop_servers
sleep 1

start_server "API"   "$ROOT/backend/public" "$API_PORT"  || exit 1
start_server "Admin" "$ROOT/admin/public"   "$ADMIN_PORT" || exit 1

echo
echo "2/3  Imtixaanada..."
echo

failed=0
total_pass=0
total_fail=0

run_suite() {
    local label="$1" file="$2" base="$3"

    reseed || { echo "     FAIL: database lama diyaarin ($label)" >&2; failed=1; return; }

    : > "$LOG"

    local out
    out="$("$PHP" "$file" "$base" 2>&1)"

    local line
    line="$(echo "$out" | tail -1 | sed 's/\x1b\[[0-9;]*m//g')"

    local pass fail
    pass="$(echo "$line" | grep -oE '^[0-9]+' || echo 0)"
    fail="$(echo "$line" | grep -oE '[0-9]+ failed' | grep -oE '^[0-9]+' || echo 0)"

    total_pass=$((total_pass + pass))
    total_fail=$((total_fail + fail))

    if [ "$fail" != "0" ]; then
        failed=1
        printf '  %-12s %s\n' "$label" "$line"
        echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^\s+FAIL' | sed 's/^/      /'
    else
        printf '  %-12s %s\n' "$label" "$line"
    fi
}

run_suite "api"        "$ROOT/backend/tests/api_test.php"        "http://127.0.0.1:$API_PORT"
run_suite "auth"       "$ROOT/backend/tests/auth_test.php"       "http://127.0.0.1:$API_PORT"
run_suite "operations" "$ROOT/backend/tests/operations_test.php" "http://127.0.0.1:$API_PORT"
run_suite "security"   "$ROOT/backend/tests/security_test.php"   "http://127.0.0.1:$API_PORT"
run_suite "alerts"     "$ROOT/backend/tests/alerts_test.php"     "http://127.0.0.1:$API_PORT"
run_suite "books"      "$ROOT/backend/tests/books_test.php"      "http://127.0.0.1:$API_PORT"
run_suite "shifts"     "$ROOT/backend/tests/shift_test.php"      "http://127.0.0.1:$API_PORT"
run_suite "plans"      "$ROOT/backend/tests/plans_test.php"      "http://127.0.0.1:$API_PORT"
run_suite "admin"      "$ROOT/admin/tests/admin_test.php"        "http://127.0.0.1:$ADMIN_PORT"

# --------------------------------------------------------------- the log

echo
echo "3/3  Log-ga khaladaadka..."

noise="$(grep -vE 'SMTP is not configured' "$LOG" 2> /dev/null | grep -c . || true)"

if [ "${noise:-0}" -gt 0 ]; then
    echo "     Wax baa la qoray — bogga Health ayay ka soo muuqan doonaan:"
    grep -vE 'SMTP is not configured' "$LOG" | tail -10 | sed 's/^/       /'
    failed=1
else
    echo "     Waa nadiif — khalad lama qorin."
fi

echo
echo "  ------------------------------------------"
printf '  %d guulaystay, %d fashilmay\n' "$total_pass" "$total_fail"
echo "  ------------------------------------------"
echo

exit "$failed"
