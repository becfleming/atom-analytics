-- =============================================================================
-- Load: rebecca_fleming.stg_pupils_history
-- =============================================================================
-- Source: de_raw.pupils    Grain: pupil_id
-- Run on every schedule. Requires ddl/stg_pupils.sql to have been deployed.
-- Permissions needed: read de_raw.pupils; write rebecca_fleming.stg_pupils_history.
-- No project is named: the job's default project decides where de_raw is
-- read from and rebecca_fleming is written.
--
-- Re-runnable: a new version is written only when a key is new, its content
-- hash changes, or it reappears after removal; a key missing from raw gets a
-- tombstone (_is_deleted_in_source = TRUE). A re-run on unchanged raw writes
-- nothing. Close + insert run in one transaction.
-- Staging only cleans (trim, ''->NULL, lowercase enums, is_deleted NULL->FALSE)
-- and enforces the grain; _source_row_count > 1 flags duplicates in raw.
-- Raw has no timestamp to pick between duplicates, so they collapse
-- conservatively: deleted if any raw row says so.
-- =============================================================================

DECLARE run_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

-- ---------------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------------
-- Versions must be written in time order, or _valid_from/_valid_to overlap.
ASSERT run_ts > COALESCE(
  (SELECT MAX(_valid_from) FROM rebecca_fleming.stg_pupils_history),
  TIMESTAMP '1970-01-01')
AS 'run_ts must be later than the latest version already in stg_pupils_history';

CREATE TEMP TABLE src_pupils AS
WITH cleaned AS (
  SELECT
    NULLIF(TRIM(pupil_id), '')  AS pupil_id,
    COALESCE(is_deleted, FALSE) AS is_deleted
  FROM de_raw.pupils
),
grouped AS (
  SELECT
    pupil_id,
    LOGICAL_OR(is_deleted) AS is_deleted,
    COUNT(*)               AS _source_row_count
  FROM cleaned
  WHERE pupil_id IS NOT NULL
  GROUP BY pupil_id
)
SELECT
  pupil_id,
  is_deleted,
  _source_row_count,
  FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(pupil_id, is_deleted, _source_row_count))) AS _row_hash
FROM grouped;

-- One row per pupil_id that needs a new version.
CREATE TEMP TABLE changes_pupils AS
WITH cur AS (
  SELECT * FROM rebecca_fleming.stg_pupils_history WHERE _is_current
)
-- New, changed, or reappeared after removal
SELECT s.pupil_id, s.is_deleted, s._source_row_count, s._row_hash,
       FALSE AS _is_deleted_in_source
FROM src_pupils AS s
LEFT JOIN cur AS c ON c.pupil_id = s.pupil_id
WHERE c.pupil_id IS NULL
   OR c._row_hash != s._row_hash
   OR c._is_deleted_in_source
UNION ALL
-- Removed from raw: tombstone with last known values
SELECT c.pupil_id, c.is_deleted, c._source_row_count, c._row_hash,
       TRUE AS _is_deleted_in_source
FROM cur AS c
LEFT JOIN src_pupils AS s ON s.pupil_id = c.pupil_id
WHERE s.pupil_id IS NULL
  AND NOT c._is_deleted_in_source;

BEGIN TRANSACTION;

UPDATE rebecca_fleming.stg_pupils_history AS h
SET _valid_to = run_ts,
    _is_current = FALSE
FROM changes_pupils AS c
WHERE h._is_current
  AND h.pupil_id = c.pupil_id;

INSERT INTO rebecca_fleming.stg_pupils_history
  (pupil_id, is_deleted, _source_row_count, _row_hash,
   _is_deleted_in_source, _valid_from, _valid_to, _is_current)
SELECT
  pupil_id, is_deleted, _source_row_count, _row_hash,
  _is_deleted_in_source, run_ts, NULL, TRUE
FROM changes_pupils;

COMMIT TRANSACTION;
