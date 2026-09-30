# Day 23 load-test baseline

Scenario: `k6-day23-extract-history.js` — authenticated history reads, quote
saves (with idempotent retry), and extraction-job submission.

## Guardrails

- Hikari `maximum-pool-size: 10` (`application.yml`). Peak load is 15 VUs so
  requests queue briefly instead of exhausting Postgres connections.
- Run against **staging** with production-like Supabase sizing, never prod.
- Watch during the run: API p50/p95/p99, error rate, Supabase DB CPU,
  `pg_stat_activity` connection count, extraction job backlog, provider spend.

## How to run

```bash
k6 run -e BASE_URL=https://staging-api.example.com \
       -e TEST_JWT=<supabase-jwt-for-load-user> \
       spring-api/load-test/k6-day23-extract-history.js
```

Requires [k6](https://k6.io/docs/get-started/installation/) (manual install —
not part of CI).

## Baseline targets (day-30 SLOs)

| Operation | Target |
|---|---|
| History reads p95 | < 1 s |
| Quote saves p95 | < 2 s |
| Extraction sync-or-job-id | ≤ 15 s |
| Error rate | < 1% |
| DB connections | below alert threshold for the whole run |
| Duplicate quotes on retry | 0 |

## Results log

| Date | Profile | p95 read | p95 save | Errors | Peak pg conns | Notes |
|---|---|---|---|---|---|---|
| _unrun_ | 5→15 VUs, 5 min | — | — | — | — | Fill in after first staging run |
