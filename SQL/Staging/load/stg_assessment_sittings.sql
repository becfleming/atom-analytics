-- =============================================================================
-- Load: rebecca_fleming.stg_assessment_sittings_history
-- =============================================================================
-- Source: de_raw.assessment_sittings    Grain: (pupil_id, session_id)
-- Run on every schedule. Requires ddl/stg_assessment_sittings.sql to have been deployed.
-- Permissions needed: read de_raw.assessment_sittings; write rebecca_fleming.stg_assessment_sittings_history.
-- No project is named: the job's default project decides where de_raw is
-- read from and rebecca_fleming is written.
--
-- Re-runnable: a new version is written only when a key is new, its content
-- hash changes, or it reappears after removal; a key missing from raw gets a
-- tombstone (_is_deleted_in_source = TRUE). A re-run on unchanged raw writes
-- nothing. Close + insert run in one transaction.
-- Staging only cleans (trim, ''->NULL, lowercase enums, is_deleted NULL->FALSE)
-- and enforces the grain; _source_row_count > 1 flags duplicates in raw.
-- Grain mirrors the responses <-> sittings join on both columns; confirm
-- against profiling. Duplicates in raw keep the most progressed version.
-- =============================================================================

DECLARE run_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

-- ---------------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------------
ASSERT run_ts > COALESCE(
  (SELECT MAX(_valid_from) FROM rebecca_fleming.stg_assessment_sittings_history),
  TIMESTAMP '1970-01-01')
AS 'run_ts must be later than the latest version already in stg_assessment_sittings_history';

CREATE TEMP TABLE src_assessment_sittings AS
WITH cleaned AS (
  SELECT
    NULLIF(TRIM(session_id), '')           AS session_id,
    NULLIF(TRIM(pupil_id), '')             AS pupil_id,
    NULLIF(TRIM(assessment_id), '')        AS assessment_id,
    NULLIF(LOWER(TRIM(session_type)), '')  AS session_type,
    NULLIF(LOWER(TRIM(style)), '')         AS style,
    year_group_at_sitting,
    total_questions,
    is_complete,
    COALESCE(is_deleted, FALSE)            AS is_deleted,
    started_at,
    finished_at
  FROM de_raw.assessment_sittings
),
hashed AS (
  SELECT
    *,
    FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(
      session_id, pupil_id, assessment_id, session_type, style, year_group_at_sitting,
      total_questions, is_complete, is_deleted, started_at, finished_at))) AS _content_hash,
    COUNT(*) OVER (PARTITION BY pupil_id, session_id) AS _source_row_count
  FROM cleaned
  WHERE session_id IS NOT NULL AND pupil_id IS NOT NULL
)
SELECT
  session_id, pupil_id, assessment_id, session_type, style, year_group_at_sitting,
  total_questions, is_complete, is_deleted, started_at, finished_at,
  _source_row_count,
  FARM_FINGERPRINT(CONCAT(CAST(_content_hash AS STRING), '|', CAST(_source_row_count AS STRING))) AS _row_hash
FROM hashed
WHERE TRUE
-- Keep the most progressed version of the sitting.
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY pupil_id, session_id
  ORDER BY finished_at DESC NULLS LAST,
           started_at  DESC NULLS LAST,
           is_complete DESC NULLS LAST,
           _content_hash
) = 1;

-- One row per (pupil_id, session_id) that needs a new version.
CREATE TEMP TABLE changes_assessment_sittings AS
WITH cur AS (
  SELECT * FROM rebecca_fleming.stg_assessment_sittings_history WHERE _is_current
)
-- New, changed, or reappeared after removal
SELECT s.session_id, s.pupil_id, s.assessment_id, s.session_type, s.style, s.year_group_at_sitting,
       s.total_questions, s.is_complete, s.is_deleted, s.started_at, s.finished_at,
       s._source_row_count, s._row_hash,
       FALSE AS _is_deleted_in_source
FROM src_assessment_sittings AS s
LEFT JOIN cur AS c ON c.pupil_id = s.pupil_id AND c.session_id = s.session_id
WHERE c.session_id IS NULL
   OR c._row_hash != s._row_hash
   OR c._is_deleted_in_source
UNION ALL
-- Removed from raw: tombstone with last known values
SELECT c.session_id, c.pupil_id, c.assessment_id, c.session_type, c.style, c.year_group_at_sitting,
       c.total_questions, c.is_complete, c.is_deleted, c.started_at, c.finished_at,
       c._source_row_count, c._row_hash,
       TRUE AS _is_deleted_in_source
FROM cur AS c
LEFT JOIN src_assessment_sittings AS s ON s.pupil_id = c.pupil_id AND s.session_id = c.session_id
WHERE s.session_id IS NULL
  AND NOT c._is_deleted_in_source;

BEGIN TRANSACTION;

UPDATE rebecca_fleming.stg_assessment_sittings_history AS h
SET _valid_to = run_ts,
    _is_current = FALSE
FROM changes_assessment_sittings AS c
WHERE h._is_current
  AND h.pupil_id = c.pupil_id
  AND h.session_id = c.session_id;

INSERT INTO rebecca_fleming.stg_assessment_sittings_history
  (session_id, pupil_id, assessment_id, session_type, style, year_group_at_sitting,
   total_questions, is_complete, is_deleted, started_at, finished_at,
   _source_row_count, _row_hash,
   _is_deleted_in_source, _valid_from, _valid_to, _is_current)
SELECT
  session_id, pupil_id, assessment_id, session_type, style, year_group_at_sitting,
  total_questions, is_complete, is_deleted, started_at, finished_at,
  _source_row_count, _row_hash,
  _is_deleted_in_source, run_ts, NULL, TRUE
FROM changes_assessment_sittings;

COMMIT TRANSACTION;
