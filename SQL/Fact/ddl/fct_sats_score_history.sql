-- =============================================================================
-- DDL: SATs score output
-- =============================================================================
-- Run on deploy, after ddl/int_sats_sitting_scores_as_of.sql and ddl/model_run_log.sql.
-- No project is named: the job's default project decides where objects go.
--
-- Objects:
--   fct_sats_score_history              One SATs score per pupil x subject x
--                                       qualifying sitting, with event-time
--                                       validity (effective_from/effective_to).
--                                       The table to migrate to the app DB.
--   (run log: ddl/model_run_log.sql, model_name = 'fct_sats_score_history')
--   pupil_subject_sats_score            View: EVERY pupil x EVERY KS2-scored
--                                       subject (English, Maths) with its current
--                                       score (NULL if never assessed).
--   pupil_subject_sats_score_as_of(ts)  Table function: each pupil's score per
--                                       subject as it stood at ts (event time).
--
-- fct_sats_score_history is derived entirely from staging + ref tables, so
-- unlike the staging history tables it CAN be rebuilt (full_refresh = TRUE).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Output table
-- Types map 1:1 to a relational DB (e.g. Postgres): STRING -> text/varchar,
-- INT64 -> integer/bigint, NUMERIC -> numeric(5,2), BOOL -> boolean,
-- TIMESTAMP -> timestamptz. No nested or repeated fields.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rebecca_fleming.fct_sats_score_history (
  sats_score_id            STRING    NOT NULL OPTIONS (description = 'Surrogate key: hex SHA-256 of pupil_id|subject_id|session_id. Stable across runs and environments; equals int_pupil_subject_session_summary.summary_id'),
  pupil_id                 STRING    NOT NULL,
  subject_id               STRING    NOT NULL,
  subject_name             STRING,
  session_id               STRING    NOT NULL OPTIONS (description = 'The sitting this score was computed from'),
  assessment_id            STRING,
  year_group_at_sitting    INT64,
  academic_year            INT64     NOT NULL OPTIONS (description = 'Academic year of the sitting, named by the year it ends (2025 = 2024/25)'),
  sitting_total_questions  INT64              OPTIONS (description = 'total_questions on the sitting (all subjects); for data-quality checks'),
  questions_presented      INT64     NOT NULL OPTIONS (description = 'Questions in this subject in the sitting (one answer per question)'),
  questions_correct        INT64     NOT NULL,
  questions_not_attempted  INT64     NOT NULL,
  percent_correct          NUMERIC(5, 2) NOT NULL OPTIONS (description = '100 * questions_correct / questions_presented'),
  ks2_subject              STRING    NOT NULL OPTIONS (description = 'KS2 curve used: reading (English) | maths (Maths)'),
  conversion_test_year     INT64     NOT NULL OPTIONS (description = 'Year of the GOV.UK conversion table applied'),
  ks2_max_raw_score        INT64     NOT NULL OPTIONS (description = 'Max raw mark of the KS2 test (reading 50, maths 110)'),
  raw_score_equivalent     INT64     NOT NULL OPTIONS (description = 'FLOOR(questions_correct x ks2_max_raw_score / questions_presented)'),
  sats_scaled_score        INT64     NOT NULL OPTIONS (description = 'SATs scaled score, 80..120'),
  is_below_scaled_range    BOOL      NOT NULL OPTIONS (description = 'TRUE if GOV.UK would award no scaled score (raw below the scoring range); score floored at 80'),
  sitting_finished_at      TIMESTAMP NOT NULL,
  effective_from           TIMESTAMP NOT NULL OPTIONS (description = "Score is the pupil's score in this subject from this time (inclusive) = sitting_finished_at"),
  effective_to             TIMESTAMP          OPTIONS (description = 'Superseded at this time (exclusive) by the next sitting; NULL while latest'),
  is_latest                BOOL      NOT NULL OPTIONS (description = "TRUE for the pupil's current score in this subject"),
  _row_hash                INT64     NOT NULL OPTIONS (description = 'Fingerprint of all business columns; rows are only rewritten when it changes'),
  _created_at              TIMESTAMP NOT NULL,
  _updated_at              TIMESTAMP NOT NULL,
  PRIMARY KEY (sats_score_id) NOT ENFORCED
)
PARTITION BY TIMESTAMP_TRUNC(sitting_finished_at, MONTH)
CLUSTER BY pupil_id, subject_id, is_latest
OPTIONS (description = 'SATs scaled score (80-120) per pupil, subject and sitting, with event-time validity. Rebuildable from staging.');

-- ---------------------------------------------------------------------------
-- Current scores: every pupil x every KS2-scored subject
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW rebecca_fleming.pupil_subject_sats_score
OPTIONS (description = 'Every current (non-deleted) pupil x every subject with a KS2 test (English, Maths), with the latest SATs scaled score. score_status = no_assessment where the pupil has no qualifying sitting in the subject.')
AS
WITH pupils AS (
  SELECT pupil_id FROM rebecca_fleming.stg_pupils WHERE NOT is_deleted
),
subjects AS (
  SELECT subject_id, subject_name
  FROM rebecca_fleming.ref_subject_ks2_mapping
  WHERE ks2_subject IS NOT NULL
)
SELECT
  p.pupil_id,
  s.subject_id,
  s.subject_name,
  IF(f.sats_score_id IS NULL, 'no_assessment', 'scored') AS score_status,
  f.sats_scaled_score,
  f.percent_correct,
  f.is_below_scaled_range,
  f.ks2_subject,
  f.conversion_test_year,
  f.session_id,
  f.sitting_finished_at,
  f.sats_score_id
FROM pupils AS p
CROSS JOIN subjects AS s
LEFT JOIN rebecca_fleming.fct_sats_score_history AS f
  ON f.pupil_id = p.pupil_id
 AND f.subject_id = s.subject_id
 AND f.is_latest;

-- ---------------------------------------------------------------------------
-- Point in time (event time): score per pupil and subject as it stood at as_of
-- For "as the model would have reported it at as_of" (ignoring later
-- corrections), use int_sats_sitting_scores_as_of(as_of) WHERE is_latest.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE FUNCTION rebecca_fleming.pupil_subject_sats_score_as_of(as_of TIMESTAMP)
OPTIONS (description = 'SATs scaled score per pupil and subject in effect at as_of (event time, current knowledge). Pupils with no sitting by as_of are absent.')
AS
SELECT
  pupil_id,
  subject_id,
  subject_name,
  sats_scaled_score,
  percent_correct,
  is_below_scaled_range,
  ks2_subject,
  conversion_test_year,
  session_id,
  sitting_finished_at,
  effective_from,
  effective_to,
  sats_score_id
FROM rebecca_fleming.fct_sats_score_history
WHERE effective_from <= as_of
  AND (effective_to IS NULL OR effective_to > as_of);
