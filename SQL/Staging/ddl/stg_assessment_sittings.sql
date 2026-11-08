-- =============================================================================
-- DDL: rebecca_fleming.stg_assessment_sittings
-- =============================================================================
-- Source: de_raw.assessment_sittings    Grain: (pupil_id, session_id) (one row per version in history)
-- Run on deploy (first time, and whenever structure changes), after
-- ddl/00_create_dataset.sql and before load/stg_assessment_sittings.sql.
-- No project is named: the job's default project decides where objects go.
--
-- Objects:
--   stg_assessment_sittings_history       Insert-only version history (SCD type 2).
--                      CREATE ... IF NOT EXISTS: a deploy never touches data.
--   stg_assessment_sittings               View: current state, rows present in raw now.
--   stg_assessment_sittings_as_of(ts)     Table function: state as loaded at timestamp ts.
--                      Both CREATE OR REPLACE, so definition changes deploy.
--
-- _valid_from/_valid_to are LOAD times (when the load saw the change), not
-- when it happened in the app.
--
-- DO NOT DROP OR REBUILD stg_assessment_sittings_history: history cannot be regenerated
-- from raw. Structural changes must be additive (ALTER TABLE ADD COLUMN).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- History table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rebecca_fleming.stg_assessment_sittings_history (
  session_id             STRING    NOT NULL OPTIONS (description = 'Session identifier; with pupil_id forms the grain'),
  pupil_id               STRING    NOT NULL,
  assessment_id          STRING,
  session_type           STRING             OPTIONS (description = 'Lowercased, trimmed'),
  style                  STRING             OPTIONS (description = 'Lowercased, trimmed'),
  year_group_at_sitting  INT64,
  total_questions        INT64,
  is_complete            BOOL               OPTIONS (description = 'As in raw; NULL kept as unknown'),
  is_deleted             BOOL      NOT NULL OPTIONS (description = 'App soft-delete flag; NULL in raw is treated as FALSE'),
  started_at             TIMESTAMP,
  finished_at            TIMESTAMP,
  _source_row_count      INT64     NOT NULL OPTIONS (description = 'Raw rows for this (pupil_id, session_id); >1 means raw had duplicates'),
  _row_hash              INT64     NOT NULL OPTIONS (description = 'Fingerprint of business columns; a change creates a new version'),
  _is_deleted_in_source  BOOL      NOT NULL OPTIONS (description = 'TRUE for a tombstone: the sitting was hard-deleted from raw. Business columns hold the last known values'),
  _valid_from            TIMESTAMP NOT NULL OPTIONS (description = 'Load time this version was first seen (inclusive)'),
  _valid_to              TIMESTAMP          OPTIONS (description = 'Load time this version was superseded (exclusive); NULL while current'),
  _is_current            BOOL      NOT NULL OPTIONS (description = 'TRUE for the latest version of each (pupil_id, session_id)'),
  PRIMARY KEY (pupil_id, session_id, _valid_from) NOT ENFORCED
)
PARTITION BY TIMESTAMP_TRUNC(started_at, MONTH)
CLUSTER BY pupil_id, session_id, _is_current
OPTIONS (description = 'Insert-only version history of de_raw.assessment_sittings. Never drop or rebuild: history cannot be regenerated from raw.');

-- ---------------------------------------------------------------------------
-- Current view and point-in-time function
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW rebecca_fleming.stg_assessment_sittings
OPTIONS (description = 'Current state of de_raw.assessment_sittings: one row per (pupil_id, session_id) present in raw now')
AS
SELECT session_id, pupil_id, assessment_id, session_type, style, year_group_at_sitting,
       total_questions, is_complete, is_deleted, started_at, finished_at,
       _source_row_count, _valid_from
FROM rebecca_fleming.stg_assessment_sittings_history
WHERE _is_current AND NOT _is_deleted_in_source;

CREATE OR REPLACE TABLE FUNCTION rebecca_fleming.stg_assessment_sittings_as_of(as_of TIMESTAMP)
OPTIONS (description = 'de_raw.assessment_sittings as loaded at as_of: one row per sitting that existed in raw at that time')
AS
SELECT session_id, pupil_id, assessment_id, session_type, style, year_group_at_sitting,
       total_questions, is_complete, is_deleted, started_at, finished_at,
       _source_row_count, _valid_from, _valid_to
FROM rebecca_fleming.stg_assessment_sittings_history
WHERE _valid_from <= as_of
  AND (_valid_to IS NULL OR _valid_to > as_of)
  AND NOT _is_deleted_in_source;
