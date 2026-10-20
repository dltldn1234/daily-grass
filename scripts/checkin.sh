#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly ACTIVITY_DIR="${ACTIVITY_DIR:-$REPO_ROOT/activity}"
readonly TIMEZONE="Asia/Seoul"
readonly MAX_PUSH_ATTEMPTS=3

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

trap 'status=$?; printf "ERROR: check-in failed at line %s (exit %s)\n" "$LINENO" "$status" >&2; exit "$status"' ERR

if (($# > 1)); then
  fail "usage: $0 [YYYY-MM-DD]"
fi

if (($# == 1)); then
  [[ ${CHECKIN_TEST_MODE:-0} == 1 ]] || fail "date override is available only to the isolated test suite"
  checkin_date=$1
  [[ $checkin_date =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail "date must use YYYY-MM-DD"
  if date -u -d "$checkin_date" +%F >/dev/null 2>&1; then
    canonical_date=$(date -u -d "$checkin_date" +%F)
  elif date -u -j -f '%Y-%m-%d' "$checkin_date" +%F >/dev/null 2>&1; then
    canonical_date=$(date -u -j -f '%Y-%m-%d' "$checkin_date" +%F)
  else
    fail "invalid calendar date: $checkin_date"
  fi
  [[ $canonical_date == "$checkin_date" ]] || fail "invalid calendar date: $checkin_date"
else
  checkin_date=$(TZ="$TIMEZONE" date +%F)
fi

month=${checkin_date:5:2}
year=${checkin_date:0:4}
case "$month" in
  01) month_name=January ;; 02) month_name=February ;; 03) month_name=March ;;
  04) month_name=April ;; 05) month_name=May ;; 06) month_name=June ;;
  07) month_name=July ;; 08) month_name=August ;; 09) month_name=September ;;
  10) month_name=October ;; 11) month_name=November ;; 12) month_name=December ;;
  *) fail "invalid month: $month" ;;
esac

mkdir -p "$ACTIVITY_DIR"
activity_file="$ACTIVITY_DIR/$year-$month.md"
line="- $checkin_date: daily check-in"

if [[ ! -f $activity_file ]]; then
  printf '# %s %s\n\n' "$month_name" "$year" > "$activity_file"
fi

if grep -Fqx -- "$line" "$activity_file"; then
  printf 'Already checked in for %s; no changes made.\n' "$checkin_date"
  exit 0
fi

printf '%s\n' "$line" >> "$activity_file"
printf 'Recorded check-in for %s in %s.\n' "$checkin_date" "$activity_file"

# Tests can point ACTIVITY_DIR at a temporary folder; only the selected log is staged.
cd "$REPO_ROOT"
relative_file=${activity_file#"$REPO_ROOT"/}
if [[ $relative_file == "$activity_file" ]]; then
  printf 'Activity directory is outside the repository; skipping Git commit.\n'
  exit 0
fi

git add -- "$relative_file"
if git diff --cached --quiet -- "$relative_file"; then
  printf 'No staged activity changes; no commit created.\n'
  exit 0
fi

git config user.name "${GIT_AUTHOR_NAME:-dltldn1234}"
git config user.email "${GIT_AUTHOR_EMAIL:-266720604+dltldn1234@users.noreply.github.com}"

git commit -m "chore: daily check-in $checkin_date" -- "$relative_file"

if ! git remote get-url origin >/dev/null 2>&1; then
  printf 'No origin remote configured; commit kept locally.\n'
  exit 0
fi

branch=${GITHUB_REF_NAME:-$(git branch --show-current)}
[[ -n $branch ]] || fail "unable to determine target branch"

for attempt in $(seq 1 "$MAX_PUSH_ATTEMPTS"); do
  if git push origin "HEAD:$branch"; then
    printf 'Pushed check-in commit to origin/%s.\n' "$branch"
    exit 0
  fi

  if ((attempt == MAX_PUSH_ATTEMPTS)); then
    fail "push failed after $MAX_PUSH_ATTEMPTS attempts"
  fi

  printf 'Push attempt %s failed; fetching origin/%s before retry.\n' "$attempt" "$branch" >&2
  git fetch origin "$branch" || fail "unable to fetch origin/$branch safely"
  remote_ref="refs/remotes/origin/$branch"
  if git show-ref --verify --quiet "$remote_ref"; then
    git rebase "$remote_ref" || fail "rebase failed; refusing to overwrite remote history"
  fi
  sleep "$((attempt * 2))"
done

fail 'push loop ended unexpectedly'
