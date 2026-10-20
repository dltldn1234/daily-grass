#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
TEST_REPO="$TEMP_DIR/repo"
mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/activity"
cp "$ROOT/scripts/checkin.sh" "$TEST_REPO/scripts/checkin.sh"
chmod +x "$TEST_REPO/scripts/checkin.sh"
cd "$TEST_REPO"
git init -q -b main
git config user.name Test
git config user.email test@example.invalid

tests=0
pass() {
  tests=$((tests + 1))
  printf 'ok %s - %s\n' "$tests" "$1"
}

run_checkin() {
  CHECKIN_TEST_MODE=1 ./scripts/checkin.sh "$@"
}

# First attendance creates the monthly file and a single commit.
run_checkin 2026-10-21 >/dev/null
grep -Fqx '# October 2026' activity/2026-10.md
grep -Fqx -- '- 2026-10-21: daily check-in' activity/2026-10.md
[[ $(git rev-list --count HEAD) == 1 ]]
pass 'first check-in creates monthly record and commit'

# Repeating the same day is an idempotent no-op.
output=$(run_checkin 2026-10-21)
[[ $output == *'Already checked in'* ]]
[[ $(git rev-list --count HEAD) == 1 ]]
pass 'duplicate date makes no file change or commit'

# A later day appends one line to the same month.
run_checkin 2026-10-22 >/dev/null
grep -Fqx -- '- 2026-10-22: daily check-in' activity/2026-10.md
[[ $(git rev-list --count HEAD) == 2 ]]
pass 'date change appends a new record'

# Month and year transitions create separate monthly files.
run_checkin 2026-11-01 >/dev/null
[[ -f activity/2026-11.md ]]
grep -Fqx '# November 2026' activity/2026-11.md
pass 'month change creates a new monthly file'
run_checkin 2027-01-01 >/dev/null
[[ -f activity/2027-01.md ]]
grep -Fqx '# January 2027' activity/2027-01.md
pass 'year change creates a correctly named file'

# Date injection is restricted to the isolated test harness.
if ./scripts/checkin.sh 2026-10-20 >/dev/null 2>&1; then
  printf 'not ok - production date override was accepted\n' >&2; exit 1
fi
pass 'date override is unavailable outside test mode'

# Invalid formats and impossible calendar dates must fail.
if run_checkin 2026-2-01 >/dev/null 2>&1; then
  printf 'not ok - invalid date format was accepted\n' >&2; exit 1
fi
pass 'invalid date format is rejected'
if run_checkin 2026-02-30 >/dev/null 2>&1; then
  printf 'not ok - impossible calendar date was accepted\n' >&2; exit 1
fi
pass 'impossible calendar date is rejected'

# No-argument date lookup must explicitly use Asia/Seoul.
MOCK_BIN="$TEMP_DIR/mock-bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/date" <<'MOCK'
#!/usr/bin/env bash
if [[ ${1:-} == '+%F' ]]; then
  [[ ${TZ:-} == Asia/Seoul ]] || exit 90
  printf '2026-12-31\n'
else
  exec /bin/date "$@"
fi
MOCK
chmod +x "$MOCK_BIN/date"
PATH="$MOCK_BIN:$PATH" run_checkin >/dev/null
grep -Fqx -- '- 2026-12-31: daily check-in' activity/2026-12.md
pass 'current date is requested in Asia/Seoul timezone'

# A failing filesystem operation must return non-zero, not report success.
mkdir -p "$TEMP_DIR/not-a-directory"
touch "$TEMP_DIR/not-a-directory/file"
if ACTIVITY_DIR="$TEMP_DIR/not-a-directory/file/child" run_checkin 2026-12-30 >/dev/null 2>&1; then
  printf 'not ok - unexpected filesystem error returned success\n' >&2; exit 1
fi
pass 'unexpected filesystem error exits non-zero'

# The already checked-in path leaves the index and commit history unchanged.
before=$(git rev-list --count HEAD)
run_checkin 2026-10-21 >/dev/null
git diff --cached --quiet
[[ $(git rev-list --count HEAD) == "$before" ]]
pass 'no-change run leaves Git index and history untouched'

printf 'Passed %s tests.\n' "$tests"
