// k6-day23-extract-history.js — Day 23 small load scenario.
//
// Covers the three risk-relevant operations: authenticated history reads,
// quote saves, and extraction-job submission. Deliberately small: peak 15 VUs
// against a Hikari maximum-pool-size of 10, so the run measures saturation
// (latency + errors + pg connections) WITHOUT exhausting the pool.
//
// Run (staging, never prod):
//   k6 run -e BASE_URL=https://staging-api.example.com \
//          -e TEST_JWT=<supabase-jwt-for-load-user> \
//          spring-api/load-test/k6-day23-extract-history.js
//
// Baseline targets (initial SLOs, day-30 plan): normal reads/writes p95 < 1s,
// quote saves < 2s, error rate < 1%. Record the actual numbers in
// load-test/baseline-day23.md after each run.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const JWT = __ENV.TEST_JWT || 'test-jwt-replace-me';

const readLatency = new Trend('history_read_ms');
const saveLatency = new Trend('quote_save_ms');
const extractLatency = new Trend('extract_submit_ms');
const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '1m', target: 5 }, // warm-up
    { duration: '3m', target: 15 }, // peak: 15 VUs, stays queueable on pool=10
    { duration: '1m', target: 0 }, // ramp-down
  ],
  thresholds: {
    history_read_ms: ['p(95)<1000'],
    quote_save_ms: ['p(95)<2000'],
    errors: ['rate<0.01'],
  },
};

function authHeaders(idemKey) {
  const h = {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${JWT}`,
  };
  if (idemKey) h['Idempotency-Key'] = idemKey;
  return h;
}

function uuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}

export default function () {
  // 1. Authenticated history read (paginated, server-side search).
  let r = http.get(`${BASE_URL}/api/quotes?page=0&size=10`, {
    headers: authHeaders(),
  });
  readLatency.add(r.timings.duration);
  check(r, { 'history read 200': (res) => res.status === 200 }) ||
    errorRate.add(1);

  // 2. Quote save with a fresh idempotency key per virtual iteration
  // (retries inside one iteration reuse the key — mirrors the app outbox).
  const key = `k6-day23-${uuid()}`;
  const quote = {
    id: uuid(),
    idempotencyKey: key,
    status: 'ready',
    trade: 'tiling',
    clientName: 'k6 Load Client',
    subtotalPaise: 1200000,
    gstPaise: 0,
    grandTotalPaise: 1200000,
    quoteDate: '2026-09-25',
    validityDays: 15,
    terms: [],
    lineItems: [],
    version: 1,
  };
  r = http.post(`${BASE_URL}/api/quotes/sync`, JSON.stringify(quote), {
    headers: authHeaders(key),
  });
  saveLatency.add(r.timings.duration);
  check(r, { 'quote save 200': (res) => res.status === 200 }) ||
    errorRate.add(1);

  // Retry the same key: must return the same record, never a duplicate.
  const retry = http.post(
    `${BASE_URL}/api/quotes/sync`,
    JSON.stringify(quote),
    { headers: authHeaders(key) },
  );
  check(retry, {
    'idempotent retry 200': (res) => res.status === 200,
    'idempotent retry same id': (res) =>
      res.json() && res.json().id === r.json().id,
  }) || errorRate.add(1);

  // 3. Extraction-job submission (small transcript, stays under the
  // 6000ms sync budget or returns a job ID for polling).
  const extract = {
    transcript: 'floor tile 120 sq ft labour',
    trade: 'tiling',
    catalogEntries: [
      {
        id: 'tile_labour',
        displayName: 'Tile Labour',
        defaultUnit: 'sq ft',
        allowedUnits: ['sq ft'],
        synonyms: ['tile labour'],
        trade: 'tiling',
      },
    ],
    rateMemory: [],
    language: 'auto',
    schemaVersion: '1.0',
    version: 1,
    idempotencyKey: `k6-extract-${uuid()}`,
  };
  r = http.post(`${BASE_URL}/api/extract`, JSON.stringify(extract), {
    headers: authHeaders(extract.idempotencyKey),
  });
  extractLatency.add(r.timings.duration);
  check(r, {
    'extract accepted (200/202)': (res) =>
      res.status === 200 || res.status === 202,
  }) || errorRate.add(1);

  sleep(1);
}
