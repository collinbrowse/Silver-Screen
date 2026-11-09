// Feature survey intake for Silver Screen.
//
// POST /survey takes one person's answers to the in-app "Pro is coming soon"
// survey and stores them in D1 (the SURVEY_DB binding, wrangler.toml). One row
// per install per survey: the app sends the same random responseID every time, so
// changing answers replaces the row instead of counting twice.
//
// Nothing here identifies a person. The row holds the picked feature ids, an
// optional free-text answer, where the survey was opened, and the app version.
// The client IP is used only for the rate limit and is never stored.
// Schema: migrations/. Analysis queries: README.md → Feature survey.

export const SURVEY_PATH = "/survey";
export const SURVEY_MAX_BODY_BYTES = 4096;
export const SURVEY_MAX_FEATURES = 20;
export const SURVEY_MAX_OTHER_CHARS = 500;
export const SURVEY_RETRY_AFTER_SECONDS = 60;
// Where the app opened the survey. Matches ProSurveySource in the app.
export const SURVEY_SOURCES = ["settings", "libraryCard"];

// Feature and survey ids are short camelCase or kebab-case slugs chosen in the app,
// so a new option needs no Worker deploy. Anything else is rejected.
const SLUG = /^[a-z][A-Za-z0-9-]{0,39}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const VERSION = /^[0-9A-Za-z.]{1,20}$/;

export const UPSERT_SQL = `INSERT INTO survey_response
  (survey_id, response_id, features, other, source, app_version, build, is_test, submitted_at, updated_at)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9)
ON CONFLICT (survey_id, response_id) DO UPDATE SET
  features = excluded.features,
  other = excluded.other,
  source = excluded.source,
  app_version = excluded.app_version,
  build = excluded.build,
  is_test = excluded.is_test,
  updated_at = excluded.updated_at`;

function jsonResponse(status, message, extraHeaders = {}) {
  return new Response(JSON.stringify({ status_message: message }), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...extraHeaders },
  });
}

// Validates the decoded body. Returns { value } with the row to store, or { error }
// with a message safe to send back (it never echoes what the client sent).
export function parseSubmission(body) {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return { error: "Body must be a JSON object." };
  }
  const { surveyID, responseID, features, other, source, appVersion, build, isTest } = body;
  if (typeof surveyID !== "string" || !SLUG.test(surveyID)) {
    return { error: "surveyID is missing or malformed." };
  }
  if (typeof responseID !== "string" || !UUID.test(responseID)) {
    return { error: "responseID must be a UUID." };
  }
  if (!Array.isArray(features) || features.length > SURVEY_MAX_FEATURES) {
    return { error: `features must be an array of at most ${SURVEY_MAX_FEATURES} ids.` };
  }
  if (!features.every((feature) => typeof feature === "string" && SLUG.test(feature))) {
    return { error: "features holds a malformed id." };
  }
  let otherText = null;
  if (other !== undefined && other !== null) {
    if (typeof other !== "string") {
      return { error: "other must be a string." };
    }
    otherText = other.trim();
    if ([...otherText].length > SURVEY_MAX_OTHER_CHARS) {
      return { error: `other is longer than ${SURVEY_MAX_OTHER_CHARS} characters.` };
    }
    if (otherText === "") {
      otherText = null;
    }
  }
  const uniqueFeatures = [...new Set(features)].sort();
  if (uniqueFeatures.length === 0 && otherText === null) {
    return { error: "Pick at least one feature or write an answer." };
  }
  if (!SURVEY_SOURCES.includes(source)) {
    return { error: "source is not one the app sends." };
  }
  if (typeof appVersion !== "string" || !VERSION.test(appVersion)) {
    return { error: "appVersion is missing or malformed." };
  }
  if (typeof build !== "string" || !VERSION.test(build)) {
    return { error: "build is missing or malformed." };
  }
  if (typeof isTest !== "boolean") {
    return { error: "isTest must be true or false." };
  }
  return {
    value: {
      surveyID,
      responseID: responseID.toLowerCase(),
      features: uniqueFeatures,
      other: otherText,
      source,
      appVersion,
      build,
      isTest,
    },
  };
}

// The bound parameters for UPSERT_SQL, in order. `now` is an ISO-8601 string.
export function upsertParams(submission, now) {
  return [
    submission.surveyID,
    submission.responseID,
    JSON.stringify(submission.features),
    submission.other,
    submission.source,
    submission.appVersion,
    submission.build,
    submission.isTest ? 1 : 0,
    now,
  ];
}

// Handles POST /survey. `clientKey` names the caller for the rate limit;
// `now` returns the current Date so tests can fix it.
export async function handleSurvey(request, env, { clientKey, now = () => new Date() }) {
  if (request.method !== "POST") {
    return jsonResponse(405, "Only POST is supported.", { Allow: "POST" });
  }
  const contentType = request.headers.get("Content-Type") ?? "";
  if (!contentType.toLowerCase().startsWith("application/json")) {
    return jsonResponse(415, "Send application/json.");
  }
  const declaredLength = Number(request.headers.get("Content-Length") ?? "0");
  if (declaredLength > SURVEY_MAX_BODY_BYTES) {
    return jsonResponse(413, "Body is too large.");
  }
  if (!env.SURVEY_DB) {
    // A missing binding is a deploy mistake. 503 so the app offers a retry.
    return jsonResponse(503, "Survey storage is not configured. See worker/README.md.");
  }
  if (env.SURVEY_RATE_LIMITER) {
    const { success } = await env.SURVEY_RATE_LIMITER.limit({ key: clientKey });
    if (!success) {
      return jsonResponse(429, "Too many requests.", { "Retry-After": String(SURVEY_RETRY_AFTER_SECONDS) });
    }
  }

  const text = await request.text();
  if (new TextEncoder().encode(text).length > SURVEY_MAX_BODY_BYTES) {
    return jsonResponse(413, "Body is too large.");
  }
  let decoded;
  try {
    decoded = JSON.parse(text);
  } catch {
    return jsonResponse(400, "Body is not valid JSON.");
  }
  const { value, error } = parseSubmission(decoded);
  if (error) {
    return jsonResponse(400, error);
  }

  try {
    await env.SURVEY_DB.prepare(UPSERT_SQL)
      .bind(...upsertParams(value, now().toISOString()))
      .run();
  } catch {
    return jsonResponse(500, "Could not save the response.");
  }
  return new Response(null, { status: 204, headers: { "Cache-Control": "no-store" } });
}
