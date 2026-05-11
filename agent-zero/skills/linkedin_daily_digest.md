# Skill: linkedin_daily_digest

Pull a curated digest of the agent's LinkedIn feed each weekday morning and
post the result to `#leads`. Criteria are iterated via conversation in
`#general`; this skill reads from the agent's own memory for the current
ruleset rather than hard-coding it.

## Trigger

Self-scheduled by Agent Zero — weekdays at 08:00 local time with ±15 min
jitter. Stored in the agent's own scheduler (`data/agent-zero/scheduler/`),
not host cron.

## Inputs

- Current lead criteria from agent memory (key: `linkedin.lead_criteria`).
  If absent, ask in `#general` before running and persist the answer.
- Recent digest history (last 7 days) to dedupe posts the agent has already
  surfaced.

## Procedure

1. **Pull feed.** Call `linkedin.get_feed` via the MCP gateway. Page through
   enough posts to cover the last ~24 hours (typically 1–3 calls).
2. **Filter.** Drop posts that don't match the lead criteria. Drop posts
   already surfaced in the last 7 days (URL or post-id match).
3. **Judge.** For each remaining post, score signal vs. noise — concrete
   hiring/buying/pain-point signals beat generic thought leadership. Keep
   the top ~5.
4. **Format.** One Discord message, each lead as:
   - One-line summary (who + signal)
   - Author + role
   - Direct link to the post
   - Optional: one suggested follow-up action (e.g. "worth a profile read")
5. **Post to `#leads`.** Single message, threaded replies for any extra
   context the agent wants to add.
6. **Record.** Append the surfaced post IDs to memory key
   `linkedin.digest_history` with today's date so step 2 can dedupe tomorrow.

## Budget

~3–5 LinkedIn API calls per run. Combined with the ad-hoc and scheduled
sub-tasks elsewhere in the routine, daily total stays under 25 calls — well
below detection thresholds.

## Failure modes

- **Session expired.** `linkedin.get_feed` returns an auth error → post a
  short note to `#audit` ("LinkedIn session expired, needs re-login") and
  stop. Do NOT retry. Operator handles via the quarterly re-login.
- **Empty feed.** Post a brief "no leads matching criteria today" to
  `#leads` so the operator knows the run completed.
- **MCP gateway unreachable.** Log to `#audit`, skip the run, do not retry
  within the same day.

## Iteration

Criteria refinement happens conversationally in `#general`. When the
operator says e.g. "ignore posts from recruiters" or "weight EU-based
companies higher", update `linkedin.lead_criteria` in memory and confirm
in `#general`. The next run uses the new criteria.
