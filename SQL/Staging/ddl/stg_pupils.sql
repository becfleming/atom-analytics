-- =============================================================================
-- DDL: rebecca_fleming.stg_pupils
-- =============================================================================
-- Source: de_raw.pupils    Grain: pupil_id (one row per version in history)
-- Run on deploy (first time, and whenever structure changes), before load/stg_pupils.sql.
-- No project is named: the job's default project decides where objects go.
--
-- Objects:
--   stg_pupils_history       Insert-only version history (SCD type 2).
--                      CREATE ... IF NOT EXISTS: a deploy never touches data.
--   stg_pupils               View: current state, rows present in raw now.
--   stg_pupils_as_of(ts)     Table function: state as loaded at timestamp ts.
--                      Both CREATE OR REPLACE, so definition changes deploy.
--
-- _valid_from/_valid_to are LOAD times (when the load saw the change), not
-- when it happened in the app.
--
-- DO NOT DROP OR REBUILD stg_pupils_history: history cannot be regenerated
-- from raw. Structural changes must be additive (ALTER TABLE ADD COLUMN).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- History table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rebecca_fleming.stg_pupils_history (
  pupil_id               STRING    NOT NULL OPTIONS (description = 'Natural key of the pupil'),
  is_deleted             BOOL      NOT NULL OPTIONS (description = 'App soft-delete flag. TRUE if any raw row marks the pupil deleted; NULL in raw is treated as FALSE'),
  _source_row_count      INT64     NOT NULL OPTIONS (description = 'Raw rows collapsed into this version; >1 means raw had duplicates'),
  _row_hash              INT64     NOT NULL OPTIONS (description = 'Fingerprint of business columns; a change creates a new version'),
  _is_deleted_in_source  BOOL      NOT NULL OPTIONS (description = 'TRUE for a tombstone: the pupil was hard-deleted from raw. Business columns hold the last known values'),
  _valid_from            TIMESTAMP NOT NULL OPTIONS (description = 'Load time this version was first seen (inclusive)'),
  _valid_to              TIMESTAMP          OPTIONS (description = 'Load time this version was superseded (exclusive); NULL while current'),
  _is_current            BOOL      NOT NULL OPTIONS (description = 'TRUE for the latest version of each pupil_id'),
  PRIMARY KEY (pupil_id, _valid_from) NOT ENFORCED
)
CLUSTER BY pupil_id, _is_current
OPTIONS (description = 'Insert-only version history of de_raw.pupils. Never drop or rebuild: history cannot be regenerated from raw.');

-- ---------------------------------------------------------------------------
-- Current view and point-in-time function
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW rebecca_fleming.stg_pupils
OPTIONS (description = 'Current state of de_raw.pupils: one row per pupil present in raw now')
AS
SELECT pupil_id, is_deleted, _source_row_count, _valid_from
FROM rebecca_fleming.stg_pupils_history
WHERE _is_current AND NOT _is_deleted_in_source;

CREATE OR REPLACE TABLE FUNCTION rebecca_fleming.stg_pupils_as_of(as_of TIMESTAMP)
OPTIONS (description = 'de_raw.pupils as loaded at as_of: one row per pupil that existed in raw at that time')
AS
SELECT pupil_id, is_deleted, _source_row_count, _valid_from, _valid_to
FROM rebecca_fleming.stg_pupils_history
WHERE _valid_from <= as_of
  AND (_valid_to IS NULL OR _valid_to > as_of)
  AND NOT _is_deleted_in_source;
