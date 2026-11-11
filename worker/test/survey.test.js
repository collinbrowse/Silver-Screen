// Validation, storage, and limit tests for POST /survey.
// Run with `node --test 'worker/test/*.test.js'` (Node 22+, no dependencies).

import assert from "node:assert/strict";
import { test } from "node:test";

import { handle } from "../src/index.js";
import { SURVEY_MAX_BODY_BYTES, SURVEY_MAX_OTHER_CHARS, UPSERT_SQL, parseSubmission } from "../src/survey.js";

const URL_BASE = "https://proxy.example.workers.dev";
const NOW = new Date("2026-11-09T18:30:00.000Z");

function validBody(overrides = {}) {
  return {
    surveyID: "pro-features-1",
    responseID: "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
    features: ["widgets", "stats", "widgets"],
    other: "  A watch party mode  ",
    source: "settings",
    appVersion: "0.1.1",
    build: "11",
    isTest: false,
    ...overrides,
  };
}

// Records every statement and its bound values, like a D1 database binding.
function fakeDatabase({ fails = false } = {}) {
  const runs = [];
  return {
    runs,
    prepare(sql) {
      return {
        bind(...params) {
          return {
            async run() {
              if (fails) {
                throw new Error("D1 unavailable");
              }
              runs.push({ sql, params });
              return { success: true };
            },
          };
        },
      };
    },
  };
}

function surveyRequest(body, { method = "POST", contentType = "application/json", ip = "203.0.113.7" } = {}) {
  const text = typeof body === "string" ? body : JSON.stringify(body);
  return new Request(`${URL_BASE}/survey`, {
    method,
    headers: { "Content-Type": contentType, "CF-Connecting-IP": ip },
    body: method === "GET" ? undefined : text,
  });
}

function send(request, env) {
  return handle(request, env, { waitUntil() {} }, { fetch: async () => assert.fail("TMDB must not be called"), now: () => NOW });
}

test("stores a valid response as one upserted row and returns 204", async () => {
  const db = fakeDatabase();

  const response = await send(surveyRequest(validBody()), { SURVEY_DB: db });

  assert.equal(response.status, 204);
  assert.equal(db.runs.length, 1);
  assert.equal(db.runs[0].sql, UPSERT_SQL);
  assert.deepEqual(db.runs[0].params, [
    "pro-features-1",
    "3f2504e0-4f89-11d3-9a0c-0305e82c3301",
    '["stats","widgets"]',
    "A watch party mode",
    "settings",
    "0.1.1",
    "11",
    0,
    "2026-11-09T18:30:00.000Z",
  ]);
});

test("upsert replaces an earlier answer from the same install instead of adding a row", () => {
  assert.match(UPSERT_SQL, /ON CONFLICT \(survey_id, response_id\) DO UPDATE/);
  assert.doesNotMatch(UPSERT_SQL.split("DO UPDATE")[1], /submitted_at/);
});

test("marks Debug-build answers as test rows", async () => {
  const db = fakeDatabase();

  await send(surveyRequest(validBody({ isTest: true })), { SURVEY_DB: db });

  assert.equal(db.runs[0].params[7], 1);
});

test("a blank other answer is stored as null", () => {
  const { value } = parseSubmission(validBody({ other: "   " }));

  assert.equal(value.other, null);
});

test("accepts free text with no features, and features with no free text", () => {
  assert.ok(parseSubmission(validBody({ features: [] })).value);
  assert.ok(parseSubmission(validBody({ other: undefined })).value);
});

test("rejects an answer with no features and no text", () => {
  const { error } = parseSubmission(validBody({ features: [], other: " " }));

  assert.match(error, /at least one/);
});

test("rejects malformed fields without echoing them", async () => {
  const cases = [
    validBody({ surveyID: "Pro Features" }),
    validBody({ responseID: "not-a-uuid" }),
    validBody({ features: "widgets" }),
    validBody({ features: ["<script>"] }),
    validBody({ features: Array.from({ length: 21 }, (_, index) => `feature${index}`) }),
    validBody({ other: 42 }),
    validBody({ other: "x".repeat(SURVEY_MAX_OTHER_CHARS + 1) }),
    validBody({ source: "pushNotification" }),
    validBody({ appVersion: "" }),
    validBody({ build: "10; DROP TABLE" }),
    validBody({ isTest: "no" }),
  ];
  for (const body of cases) {
    const db = fakeDatabase();
    const response = await send(surveyRequest(body), { SURVEY_DB: db });
    const payload = await response.json();

    assert.equal(response.status, 400, JSON.stringify(body));
    assert.equal(db.runs.length, 0);
    assert.doesNotMatch(payload.status_message, /script|DROP|pushNotification/);
  }
});

test("counts characters, not UTF-16 units, against the free-text limit", () => {
  const emoji = "🎬".repeat(SURVEY_MAX_OTHER_CHARS);

  assert.ok(parseSubmission(validBody({ other: emoji })).value);
});

test("rejects a body that is not JSON", async () => {
  const response = await send(surveyRequest("{not json"), { SURVEY_DB: fakeDatabase() });

  assert.equal(response.status, 400);
});

test("rejects a body over the size limit before parsing it", async () => {
  const db = fakeDatabase();
  const padded = validBody({ other: "x".repeat(SURVEY_MAX_BODY_BYTES) });

  const response = await send(surveyRequest(padded), { SURVEY_DB: db });

  assert.equal(response.status, 413);
  assert.equal(db.runs.length, 0);
});

test("rejects other methods and content types", async () => {
  const env = { SURVEY_DB: fakeDatabase() };

  const get = await send(surveyRequest(null, { method: "GET" }), env);
  const form = await send(surveyRequest(validBody(), { contentType: "text/plain" }), env);

  assert.equal(get.status, 405);
  assert.equal(get.headers.get("Allow"), "POST");
  assert.equal(form.status, 415);
});

test("returns 503 when the D1 binding is missing, so the app can retry later", async () => {
  const response = await send(surveyRequest(validBody()), {});

  assert.equal(response.status, 503);
});

test("returns 500 when D1 fails", async () => {
  const response = await send(surveyRequest(validBody()), { SURVEY_DB: fakeDatabase({ fails: true }) });

  assert.equal(response.status, 500);
});

test("rate-limits survey writes by client IP with their own limiter", async () => {
  const keys = [];
  const db = fakeDatabase();
  const env = {
    SURVEY_DB: db,
    SURVEY_RATE_LIMITER: {
      async limit({ key }) {
        keys.push(key);
        return { success: false };
      },
    },
    RATE_LIMITER: {
      async limit() {
        assert.fail("The TMDB limiter must not count survey writes");
      },
    },
  };

  const response = await send(surveyRequest(validBody()), env);

  assert.equal(response.status, 429);
  assert.equal(response.headers.get("Retry-After"), "60");
  assert.deepEqual(keys, ["203.0.113.7"]);
  assert.equal(db.runs.length, 0);
});

test("survey responses are never cached", async () => {
  const response = await send(surveyRequest(validBody()), { SURVEY_DB: fakeDatabase() });

  assert.equal(response.headers.get("Cache-Control"), "no-store");
});
