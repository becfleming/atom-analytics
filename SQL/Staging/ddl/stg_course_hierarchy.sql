-- =============================================================================
-- DDL: rebecca_fleming.stg_course_hierarchy
-- =============================================================================
-- Source: de_raw.course_hierarchy    Grain: question_id (one row per version in history)
-- Run on deploy (first time, and whenever structure changes), after
-- ddl/00_create_dataset.sql and before load/stg_course_hierarchy.sql.
-- No project is named: the job's default project decides where objects go.
--
-- Objects:
--   stg_course_hierarchy_history       Insert-only version history (SCD type 2).
--                      CREATE ... IF NOT EXISTS: a deploy never touches data.
--   stg_course_hierarchy               View: current state, rows present in raw now.
--   stg_course_hierarchy_as_of(ts)     Table function: state as loaded at timestamp ts.
--                      Both CREATE OR REPLACE, so definition changes deploy.
--
-- _valid_from/_valid_to are LOAD times (when the load saw the change), not
-- when it happened in the app.
--
-- DO NOT DROP OR REBUILD stg_course_hierarchy_history: history cannot be regenerated
-- from raw. Structural changes must be additive (ALTER TABLE ADD COLUMN).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- History table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rebecca_fleming.stg_course_hierarchy_history (
  question_id            STRING    NOT NULL OPTIONS (description = 'Natural key of the question'),
  atom_id                STRING             OPTIONS (description = 'Lowest level of the hierarchy above question'),
  subtopic_id            STRING,
  topic_id               STRING,
  subject_id             STRING,
  subject_name           STRING             OPTIONS (description = 'Trimmed; original casing kept for display'),
  _source_row_count      INT64     NOT NULL OPTIONS (description = 'Raw rows for this question_id; >1 means raw had duplicate or conflicting placements'),
  _row_hash              INT64     NOT NULL OPTIONS (description = 'Fingerprint of business columns; a change creates a new version'),
  _is_deleted_in_source  BOOL      NOT NULL OPTIONS (description = 'TRUE for a tombstone: the question was removed from raw. Business columns hold the last known placement'),
  _valid_from            TIMESTAMP NOT NULL OPTIONS (description = 'Load time this version was first seen (inclusive)'),
  _valid_to              TIMESTAMP          OPTIONS (description = 'Load time this version was superseded (exclusive); NULL while current'),
  _is_current            BOOL      NOT NULL OPTIONS (description = 'TRUE for the latest version of each question_id'),
  PRIMARY KEY (question_id, _valid_from) NOT ENFORCED
)
CLUSTER BY question_id, subject_id, _is_current
OPTIONS (description = 'Insert-only version history of de_raw.course_hierarchy. Never drop or rebuild: history cannot be regenerated from raw.');

-- ---------------------------------------------------------------------------
-- Current view and point-in-time function
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW rebecca_fleming.stg_course_hierarchy
OPTIONS (description = 'Current state of de_raw.course_hierarchy: one row per question present in raw now')
AS
SELECT question_id, atom_id, subtopic_id, topic_id, subject_id, subject_name,
       _source_row_count, _valid_from
FROM rebecca_fleming.stg_course_hierarchy_history
WHERE _is_current AND NOT _is_deleted_in_source;

CREATE OR REPLACE TABLE FUNCTION rebecca_fleming.stg_course_hierarchy_as_of(as_of TIMESTAMP)
OPTIONS (description = 'de_raw.course_hierarchy as loaded at as_of: one row per question that existed in raw at that time')
AS
SELECT question_id, atom_id, subtopic_id, topic_id, subject_id, subject_name,
       _source_row_count, _valid_from, _valid_to
FROM rebecca_fleming.stg_course_hierarchy_history
WHERE _valid_from <= as_of
  AND (_valid_to IS NULL OR _valid_to > as_of)
  AND NOT _is_deleted_in_source;
