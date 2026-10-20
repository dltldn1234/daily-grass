# Daily Grass Bot

Daily Grass Bot records one check-in commit per day in the `dltldn1234` GitHub repository. It is an automated attendance log only; it does not create or simulate development work.

## How it works

GitHub Actions runs `scripts/checkin.sh` daily at 12:37 in `Asia/Seoul`, and the workflow can also be started with **Actions → Daily check-in → Run workflow**. The script selects the current Korean calendar date, appends it to `activity/YYYY-MM.md`, and creates `chore: daily check-in YYYY-MM-DD`. If today's entry already exists, it exits without a commit. A workflow concurrency group serializes scheduled and manual runs. Push attempts are limited to three; after a rejected push, the script fetches the target branch and rebases before retrying, and exits unsuccessfully if it cannot safely update.

GitHub may delay scheduled workflows during high load. The configured time is a target, not a guarantee. Scheduled workflows run only from the repository's default branch.

## Repository layout

```text
.github/workflows/daily-commit.yml  Scheduled and manual check-in
.github/workflows/test.yml          Automated test workflow
scripts/checkin.sh                  Check-in and Git push logic
tests/test-checkin.sh               Isolated shell integration tests
activity/YYYY-MM.md                 Monthly attendance history
```

## Local use

Requirements: Bash, Git, and standard `date`, `grep`, and `seq` commands.

```bash
./scripts/checkin.sh
```

The script uses the current date in `Asia/Seoul`. In a Git checkout with an `origin` remote it commits and attempts to push to the current branch. Without an `origin`, it keeps the commit locally. A date override is accepted only when `CHECKIN_TEST_MODE=1`; the test harness sets this in its isolated temporary repository. Normal runs always use today's Korean date, so the production workflow cannot backfill an arbitrary date.

Run the isolated tests with:

```bash
./tests/test-checkin.sh
```

Tests create a temporary Git repository and never push to GitHub or modify the project's `activity` files.

## GitHub Actions setup

1. Push the project to `main` and make `main` the repository's default branch.
2. In **Settings → Actions → General → Workflow permissions**, allow workflows to write to the repository if the organization or repository policy otherwise makes `GITHUB_TOKEN` read-only. The workflow requests only `contents: write` for the check-in job; the test workflow has `contents: read`.
3. Confirm Actions are enabled. Use **Actions → Daily check-in → Run workflow** on `main` for a manual run. Runs selected from other branches are skipped. Manual runs use the current Korean date too, so they will not make a second same-day commit.
4. Inspect the workflow run and the `activity` file on `main` to confirm the result.

No personal access token or separately stored secret is needed. The workflow uses GitHub's built-in `GITHUB_TOKEN`.

## Attendance files

Each file has a month heading and one ISO date per line, for example:

```text
# October 2026

- 2026-10-21: daily check-in
```

GitHub profile contributions generally require the commit email to be associated with the account and the commit to land on the default branch (or a qualifying `gh-pages` branch). The workflow uses the account's ID-based noreply address (`266720604+dltldn1234@users.noreply.github.com`) and author name `dltldn1234`. Contribution display can take time and is governed by GitHub's rules, so it is not guaranteed to appear immediately.

## Troubleshooting and recovery

- If a run fails, open its log under **Actions**, fix the cause, and rerun the workflow. A failed push is reported as a failed run.
- If `GITHUB_TOKEN` cannot push, check repository or organization Actions workflow permissions and branch protection rules. No secret token should be added to the repository.
- If a date line already exists, a successful no-op run is expected; the script does not make another commit.
- If a monthly file needs manual correction, edit it in a reviewed commit on `main`. Do not rerun with an arbitrary date to backfill attendance.

## Pause automation

In **Actions → Daily check-in → … → Disable workflow** to pause the schedule, or remove the schedule trigger in `.github/workflows/daily-commit.yml`. Re-enable the workflow from the same Actions page when ready.

## License

MIT. See [LICENSE](LICENSE).
