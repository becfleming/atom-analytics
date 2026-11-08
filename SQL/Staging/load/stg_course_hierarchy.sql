-- =============================================================================
-- Load: rebecca_fleming.stg_course_hierarchy_history
-- =============================================================================
-- Source: de_raw.course_hierarchy    Grain: question_id
-- Run on every schedule. Requires ddl/stg_course_hierarchy.sql to have been deployed.
-- Permissions needed: read de_raw.course_hierarchy; write rebecca_fleming.stg_course_hierarchy_history.
-- No project is named: the job's default project decides where de_raw is
-- read from and rebecca_fleming is written.
--
-- Re-runnable: a new version is written only when a key is new, its content
-- hash changes, or it reappears after removal; a key missing from raw gets a
-- tombstone (_is_deleted_in_source = TRUE). A re-run on unchanged raw writes
-- nothing. Close + insert run in one transaction.
-- Staging only cleans (trim, ''->NULL, lowercase enums, is_deleted NULL->FALSE)
-- and enforces the grain; _source_row_count > 1 flags duplicates in raw.
-- Raw has no timestamp to pick between duplicate placements of a question, so
-- one is chosen arbitrarily but deterministically.
-- =============================================================================

DECLARE run_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

-- ---------------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------------
ASSERT run_ts > COALESCE(
  (SELECT MAX(_valid_from) FROM rebecca_fleming.stg_course_hierarchy_history),
  TIMESTAMP '1970-01-01')
AS 'run_ts must be later than the latest version already in stg_course_hierarchy_history';

CREATE TEMP TABLE src_course_hierarchy AS
WITH cleaned AS (
  SELECT
    NULLIF(TRIM(question_id), '')  AS question_id,
    NULLIF(TRIM(atom_id), '')      AS atom_id,
    NULLIF(TRIM(subtopic_id), '')  AS subtopic_id,
    NULLIF(TRIM(topic_id), '')     AS topic_id,
    NULLIF(TRIM(subject_id), '')   AS subject_id,
    NULLIF(TRIM(subject_name), '') AS subject_name
  FROM de_raw.course_hierarchy
),
hashed AS (
  SELECT
    *,
    FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(
      question_id, atom_id, subtopic_id, topic_id, subject_id, subject_name))) AS _content_hash,
    COUNT(*) OVER (PARTITION BY question_id) AS _source_row_count
  FROM cleaned
  WHERE question_id IS NOT NULL
)
SELECT
  question_id, atom_id, subtopic_id, topic_id, subject_id, subject_name,
  _source_row_count,
  -- Includes the duplicate count, so a change in duplication is a new version.
  FARM_FINGERPRINT(CONCAT(CAST(_content_hash AS STRING), '|', CAST(_source_row_count AS STRING))) AS _row_hash
FROM hashed
WHERE TRUE
QUALIFY ROW_NUMBER() OVER (PARTITION BY question_id ORDER BY _content_hash) = 1;

-- One row per question_id that needs a new version.
CREATE TEMP TABLE changes_course_hierarchy AS
WITH cur AS (
  SELECT * FROM rebecca_fleming.stg_course_hierarchy_history WHERE _is_current
)
-- New, changed, or reappeared after removal
SELECT s.question_id, s.atom_id, s.subtopic_id, s.topic_id, s.subject_id, s.subject_name,
       s._source_row_count, s._row_hash,
       FALSE AS _is_deleted_in_source
FROM src_course_hierarchy AS s
LEFT JOIN cur AS c ON c.question_id = s.question_id
WHERE c.question_id IS NULL
   OR c._row_hash != s._row_hash
   OR c._is_deleted_in_source
UNION ALL
-- Removed from raw: tombstone with last known placement
SELECT c.question_id, c.atom_id, c.subtopic_id, c.topic_id, c.subject_id, c.subject_name,
       c._source_row_count, c._row_hash,
       TRUE AS _is_deleted_in_source
FROM cur AS c
LEFT JOIN src_course_hierarchy AS s ON s.question_id = c.question_id
WHERE s.question_id IS NULL
  AND NOT c._is_deleted_in_source;

BEGIN TRANSACTION;

UPDATE rebecca_fleming.stg_course_hierarchy_history AS h
SET _valid_to = run_ts,
    _is_current = FALSE
FROM changes_course_hierarchy AS c
WHERE h._is_current
  AND h.question_id = c.question_id;

INSERT INTO rebecca_fleming.stg_course_hierarchy_history
  (question_id, atom_id, subtopic_id, topic_id, subject_id, subject_name,
   _source_row_count, _row_hash,
   _is_deleted_in_source, _valid_from, _valid_to, _is_current)
SELECT
  question_id, atom_id, subtopic_id, topic_id, subject_id, subject_name,
  _source_row_count, _row_hash,
  _is_deleted_in_source, run_ts, NULL, TRUE
FROM changes_course_hierarchy;

COMMIT TRANSACTION;
