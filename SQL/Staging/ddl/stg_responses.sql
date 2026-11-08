-- =============================================================================
-- DDL: rebecca_fleming.stg_responses
-- =============================================================================
-- Source: de_raw.responses    Grain: response_id (one row per version in history)
-- Run on deploy (first time, and whenever structure changes), after
-- ddl/00_create_dataset.sql and before load/stg_responses.sql.
-- No project is named: the job's default project decides where objects go.
--
-- Objects:
--   stg_responses_history       Insert-only version history (SCD type 2).
--                      CREATE ... IF NOT EXISTS: a deploy never touches data.
--   stg_responses               View: current state, rows present in raw now.
--   stg_responses_as_of(ts)     Table function: state as loaded at timestamp ts.
--                      Both CREATE OR REPLACE, so definition changes deploy.
--
-- _valid_from/_valid_to are LOAD times (when the load saw the change), not
-- when it happened in the app.
--
-- DO NOT DROP OR REBUILD stg_responses_history: history cannot be regenerated
-- from raw. Structural changes must be additive (ALTER TABLE ADD COLUMN).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- History table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rebecca_fleming.stg_responses_history (
  response_id            STRING    NOT NULL OPTIONS (description = 'Natural key of the response'),
  pupil_id               STRING    NOT NULL,
  session_id             STRING    NOT NULL OPTIONS (description = 'Joins to stg_assessment_sittings on (pupil_id, session_id)'),
  question_id            STRING             OPTIONS (description = 'Joins to stg_course_hierarchy.question_id'),
  session_type           STRING             OPTIONS (description = 'Lowercased, trimmed; as recorded on the response'),
  question_number        INT64,
  is_correct             BOOL               OPTIONS (description = 'As in raw; NULL kept as unknown'),
  is_no_attempt          BOOL               OPTIONS (description = 'As in raw; NULL kept as unknown'),
  seconds_taken          INT64,
  answered_at            TIMESTAMP          OPTIONS (description = 'Event time; partition column'),
  _source_row_count      INT64     NOT NULL OPTIONS (description = 'Raw rows for this response_id seen in the load window; >1 means raw had duplicates'),
  _row_hash              INT64     NOT NULL OPTIONS (description = 'Fingerprint of business columns; a change creates a new version'),
  _is_deleted_in_source  BOOL      NOT NULL OPTIONS (description = 'TRUE for a tombstone: the response was removed from raw. Business columns hold the last known values'),
  _valid_from            TIMESTAMP NOT NULL OPTIONS (description = 'Load time this version was first seen (inclusive)'),
  _valid_to              TIMESTAMP          OPTIONS (description = 'Load time this version was superseded (exclusive); NULL while current'),
  _is_current            BOOL      NOT NULL OPTIONS (description = 'TRUE for the latest version of each response_id'),
  PRIMARY KEY (response_id, _valid_from) NOT ENFORCED
)
PARTITION BY DATE(answered_at)
CLUSTER BY pupil_id, session_id, question_id, _is_current
OPTIONS (description = 'Insert-only version history of de_raw.responses. Never drop or rebuild: earlier versions cannot be regenerated from raw.');

-- ---------------------------------------------------------------------------
-- Current view and point-in-time function
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW rebecca_fleming.stg_responses
OPTIONS (description = 'Current state of de_raw.responses: one row per response present in raw now')
AS
SELECT response_id, pupil_id, session_id, question_id, session_type, question_number,
       is_correct, is_no_attempt, seconds_taken, answered_at,
       _source_row_count, _valid_from
FROM rebecca_fleming.stg_responses_history
WHERE _is_current AND NOT _is_deleted_in_source;

CREATE OR REPLACE TABLE FUNCTION rebecca_fleming.stg_responses_as_of(as_of TIMESTAMP)
OPTIONS (description = 'de_raw.responses as loaded at as_of: one row per response that existed in raw at that time. Add an answered_at filter to prune partitions.')
AS
SELECT response_id, pupil_id, session_id, question_id, session_type, question_number,
       is_correct, is_no_attempt, seconds_taken, answered_at,
       _source_row_count, _valid_from, _valid_to
FROM rebecca_fleming.stg_responses_history
WHERE _valid_from <= as_of
  AND (_valid_to IS NULL OR _valid_to > as_of)
  AND NOT _is_deleted_in_source;
