-- One row per install per survey. The app sends the same random responseID each
-- time, so changing answers updates the row. Written by src/survey.js.
CREATE TABLE survey_response (
  survey_id TEXT NOT NULL,
  response_id TEXT NOT NULL,
  -- JSON array of feature ids, sorted and de-duplicated, such as ["stats","widgets"].
  features TEXT NOT NULL,
  -- The optional "Anything else?" answer, or NULL.
  other TEXT,
  -- Where the survey was opened: settings or libraryCard.
  source TEXT NOT NULL,
  app_version TEXT NOT NULL,
  build TEXT NOT NULL,
  -- 1 for Debug builds (simulator, Xcode runs). Leave these out of every count.
  is_test INTEGER NOT NULL DEFAULT 0,
  -- ISO-8601 UTC. submitted_at is the first answer, updated_at the latest change.
  submitted_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (survey_id, response_id)
);

CREATE INDEX survey_response_by_survey ON survey_response (survey_id, is_test, submitted_at);
