-- =============================================================================
-- Load: rebecca_fleming.stg_responses_history
-- =============================================================================
-- Source: de_raw.responses    Grain: response_id
-- Run on every schedule. Requires ddl/stg_responses.sql to have been deployed.
-- Permissions needed: read de_raw.responses; write rebecca_fleming.stg_responses_history.
-- No project is named: the job's default project decides where de_raw is
-- read from and rebecca_fleming is written.
--
-- Re-runnable: a new version is written only when a key is new, its content
-- hash changes, or it reappears after removal; a key missing from raw gets a
-- tombstone (_is_deleted_in_source = TRUE). A re-run on unchanged raw writes
-- nothing. Close + insert run in one transaction.
-- Staging only cleans (trim, ''->NULL, lowercase enums, is_deleted NULL->FALSE)
-- and enforces the grain; _source_row_count > 1 flags duplicates in raw.
-- High volume: raw is read incrementally from (latest staged answered_at -
-- lookback), plus NULL answered_at rows. Set full_refresh = TRUE to rescan all
-- of raw. Change detection compares against ALL current versions (narrow
-- column scan) so a moved answered_at cannot create two current versions.
-- Hard deletes are only detected inside the load window.
-- =============================================================================

DECLARE run_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
DECLARE full_refresh BOOL DEFAULT FALSE;         -- TRUE = rescan all of raw responses
DECLARE responses_lookback_days INT64 DEFAULT 3; -- re-process late-arriving responses
DECLARE responses_cutoff TIMESTAMP;              -- set after the table exists
DECLARE responses_is_full BOOL;

-- ---------------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------------
ASSERT run_ts > COALESCE(
  (SELECT MAX(_valid_from) FROM rebecca_fleming.stg_responses_history),
  TIMESTAMP '1970-01-01')
AS 'run_ts must be later than the latest version already in stg_responses_history';

-- Incremental window. Empty table or full_refresh = TRUE -> full scan of raw.
SET responses_cutoff = (
  SELECT TIMESTAMP_SUB(MAX(answered_at), INTERVAL responses_lookback_days DAY)
  FROM rebecca_fleming.stg_responses_history
  WHERE _is_current AND NOT _is_deleted_in_source
);
SET responses_is_full = full_refresh OR responses_cutoff IS NULL;

CREATE TEMP TABLE src_responses AS
WITH cleaned AS (
  SELECT
    NULLIF(TRIM(response_id), '')          AS response_id,
    NULLIF(TRIM(pupil_id), '')             AS pupil_id,
    NULLIF(TRIM(session_id), '')           AS session_id,
    NULLIF(TRIM(question_id), '')          AS question_id,
    NULLIF(LOWER(TRIM(session_type)), '')  AS session_type,
    question_number,
    is_correct,
    is_no_attempt,
    seconds_taken,
    answered_at
  FROM de_raw.responses
  WHERE responses_is_full
     OR answered_at >= responses_cutoff
     OR answered_at IS NULL
),
hashed AS (
  SELECT
    *,
    FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(
      response_id, pupil_id, session_id, question_id, session_type, question_number,
      is_correct, is_no_attempt, seconds_taken, answered_at))) AS _content_hash,
    COUNT(*) OVER (PARTITION BY response_id) AS _source_row_count
  FROM cleaned
  WHERE response_id IS NOT NULL AND pupil_id IS NOT NULL AND session_id IS NOT NULL
)
SELECT
  response_id, pupil_id, session_id, question_id, session_type, question_number,
  is_correct, is_no_attempt, seconds_taken, answered_at,
  _source_row_count,
  FARM_FINGERPRINT(CONCAT(CAST(_content_hash AS STRING), '|', CAST(_source_row_count AS STRING))) AS _row_hash
FROM hashed
WHERE TRUE
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY response_id
  ORDER BY answered_at DESC NULLS LAST, _content_hash
) = 1;

-- One row per response_id that needs a new version.
CREATE TEMP TABLE changes_responses AS
-- New, changed, or reappeared after removal: compared against all current
-- versions (narrow column scan) so a moved answered_at cannot create duplicates.
SELECT s.response_id, s.pupil_id, s.session_id, s.question_id, s.session_type, s.question_number,
       s.is_correct, s.is_no_attempt, s.seconds_taken, s.answered_at,
       s._source_row_count, s._row_hash,
       FALSE AS _is_deleted_in_source
FROM src_responses AS s
LEFT JOIN (
  SELECT response_id, _row_hash, _is_deleted_in_source
  FROM rebecca_fleming.stg_responses_history
  WHERE _is_current
) AS c ON c.response_id = s.response_id
WHERE c.response_id IS NULL
   OR c._row_hash != s._row_hash
   OR c._is_deleted_in_source
UNION ALL
-- Removed from raw: only current versions inside the load window can be
-- judged, because only that slice of raw was read.
SELECT c.response_id, c.pupil_id, c.session_id, c.question_id, c.session_type, c.question_number,
       c.is_correct, c.is_no_attempt, c.seconds_taken, c.answered_at,
       c._source_row_count, c._row_hash,
       TRUE AS _is_deleted_in_source
FROM (
  SELECT *
  FROM rebecca_fleming.stg_responses_history
  WHERE _is_current
    AND NOT _is_deleted_in_source
    AND (responses_is_full OR answered_at >= responses_cutoff OR answered_at IS NULL)
) AS c
LEFT JOIN src_responses AS s ON s.response_id = c.response_id
WHERE s.response_id IS NULL;

BEGIN TRANSACTION;

UPDATE rebecca_fleming.stg_responses_history AS h
SET _valid_to = run_ts,
    _is_current = FALSE
FROM changes_responses AS c
WHERE h._is_current
  AND h.response_id = c.response_id;

INSERT INTO rebecca_fleming.stg_responses_history
  (response_id, pupil_id, session_id, question_id, session_type, question_number,
   is_correct, is_no_attempt, seconds_taken, answered_at,
   _source_row_count, _row_hash,
   _is_deleted_in_source, _valid_from, _valid_to, _is_current)
SELECT
  response_id, pupil_id, session_id, question_id, session_type, question_number,
  is_correct, is_no_attempt, seconds_taken, answered_at,
  _source_row_count, _row_hash,
  _is_deleted_in_source, run_ts, NULL, TRUE
FROM changes_responses;

COMMIT TRANSACTION;
