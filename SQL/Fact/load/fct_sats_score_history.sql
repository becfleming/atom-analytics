-- =============================================================================
-- Load: rebecca_fleming.fct_sats_score_history
-- =============================================================================
-- Run on every schedule, after the staging loads, the ref_* loads and
-- load/int_pupil_subject_session_summary.sql.
-- No project is named: the job's default project decides where objects go.
--
-- Incremental by pupil:
--   1. Pupils to reprocess = int_changed_pupils(change window start). The
--      window starts reprocess_overlap_hours before this model's last run, so
--      a staging load that committed late is still picked up.
--   2. Recompute ALL scores for those pupils with int_sats_sitting_scores_as_of
--      (run_ts), so effective_to / is_latest are always consistent.
--   3. In one transaction: delete their rows that no longer exist (deleted
--      pupil or sitting, question moved subject), upsert rows whose content
--      hash changed, and write model_run_log.
--   Full refresh (every pupil) on the first run, when full_refresh = TRUE, or
--   automatically when the ref_* tables or the definition of the logic
--   functions have changed.
--
-- Re-runnable: rows are only written when their content changes, so a second
-- run with unchanged inputs leaves fct_sats_score_history untouched (only a
-- run-log row is added).
-- =============================================================================

DECLARE this_model STRING DEFAULT 'fct_sats_score_history';
DECLARE run_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
DECLARE full_refresh BOOL DEFAULT FALSE;          -- TRUE = recompute every pupil
DECLARE reprocess_overlap_hours INT64 DEFAULT 24; -- safety margin for late-committing staging loads
DECLARE prev_run_ts TIMESTAMP;
DECLARE prev_input_fingerprint INT64;
DECLARE input_fingerprint INT64;
DECLARE is_full BOOL;
DECLARE change_window_start TIMESTAMP;
DECLARE pupils_reprocessed INT64;
DECLARE rows_deleted INT64;
DECLARE rows_upserted INT64;

-- ---------------------------------------------------------------------------
-- Watermark, reference-data and logic check
-- ---------------------------------------------------------------------------
SET prev_run_ts = (
  SELECT MAX(l.run_ts) FROM rebecca_fleming.model_run_log AS l WHERE l.model_name = this_model
);
SET prev_input_fingerprint = (
  SELECT l.input_fingerprint FROM rebecca_fleming.model_run_log AS l
  WHERE l.model_name = this_model AND l.run_ts = prev_run_ts
);

ASSERT run_ts > COALESCE(prev_run_ts, TIMESTAMP '1970-01-01')
AS 'run_ts must be later than the previous run of this model in model_run_log';

-- Changing the conversion tables, the subject mapping, or the logic of any
-- function the scores are computed from forces a full refresh.
SET input_fingerprint = (
  SELECT
      COALESCE((SELECT BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(c)))
                FROM rebecca_fleming.ref_ks2_scaled_score_conversion AS c), 0)
    ^ COALESCE((SELECT BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(m.subject_id, m.ks2_subject))))
                FROM rebecca_fleming.ref_subject_ks2_mapping AS m), 0)
    ^ COALESCE((SELECT BIT_XOR(FARM_FINGERPRINT(CONCAT(r.routine_name, '|', r.routine_definition)))
                FROM rebecca_fleming.INFORMATION_SCHEMA.ROUTINES AS r
                WHERE r.routine_name IN (
                  'int_sats_sitting_scores_as_of',
                  'int_pupil_subject_session_summary_as_of',
                  'stg_pupils_as_of', 'stg_assessment_sittings_as_of',
                  'stg_responses_as_of', 'stg_course_hierarchy_as_of')), 0)
);

SET is_full = full_refresh
           OR prev_run_ts IS NULL
           OR prev_input_fingerprint IS DISTINCT FROM input_fingerprint;

SET change_window_start = IF(is_full, NULL,
  TIMESTAMP_SUB(prev_run_ts, INTERVAL reprocess_overlap_hours HOUR));

-- ---------------------------------------------------------------------------
-- 1. Pupils to reprocess
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE affected_pupils AS
SELECT pupil_id FROM rebecca_fleming.int_changed_pupils(change_window_start)
UNION DISTINCT
-- Full refresh: also clear pupils in the output but no longer anywhere in staging.
SELECT pupil_id FROM rebecca_fleming.fct_sats_score_history WHERE is_full;

SET pupils_reprocessed = (SELECT COUNT(*) FROM affected_pupils);

-- ---------------------------------------------------------------------------
-- 2. Recompute every score for those pupils
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE new_scores AS
SELECT
  TO_HEX(SHA256(CONCAT(s.pupil_id, '|', s.subject_id, '|', s.session_id))) AS sats_score_id,
  s.*,
  FARM_FINGERPRINT(TO_JSON_STRING(s)) AS _row_hash
FROM rebecca_fleming.int_sats_sitting_scores_as_of(run_ts) AS s
WHERE s.pupil_id IN (SELECT pupil_id FROM affected_pupils);

-- ---------------------------------------------------------------------------
-- 3. Apply
-- ---------------------------------------------------------------------------
BEGIN TRANSACTION;

DELETE FROM rebecca_fleming.fct_sats_score_history AS f
WHERE f.pupil_id IN (SELECT pupil_id FROM affected_pupils)
  AND NOT EXISTS (SELECT 1 FROM new_scores AS n WHERE n.sats_score_id = f.sats_score_id);

SET rows_deleted = @@row_count;

MERGE rebecca_fleming.fct_sats_score_history AS t
USING new_scores AS s
ON t.sats_score_id = s.sats_score_id
WHEN MATCHED AND t._row_hash != s._row_hash THEN UPDATE SET
  pupil_id                = s.pupil_id,
  subject_id              = s.subject_id,
  subject_name            = s.subject_name,
  session_id              = s.session_id,
  assessment_id           = s.assessment_id,
  year_group_at_sitting   = s.year_group_at_sitting,
  academic_year           = s.academic_year,
  sitting_total_questions = s.sitting_total_questions,
  questions_presented     = s.questions_presented,
  questions_correct       = s.questions_correct,
  questions_not_attempted = s.questions_not_attempted,
  percent_correct         = s.percent_correct,
  ks2_subject             = s.ks2_subject,
  conversion_test_year    = s.conversion_test_year,
  ks2_max_raw_score       = s.ks2_max_raw_score,
  raw_score_equivalent    = s.raw_score_equivalent,
  sats_scaled_score       = s.sats_scaled_score,
  is_below_scaled_range   = s.is_below_scaled_range,
  sitting_finished_at     = s.sitting_finished_at,
  effective_from          = s.effective_from,
  effective_to            = s.effective_to,
  is_latest               = s.is_latest,
  _row_hash               = s._row_hash,
  _updated_at             = run_ts
WHEN NOT MATCHED BY TARGET THEN INSERT (
  sats_score_id, pupil_id, subject_id, subject_name, session_id, assessment_id,
  year_group_at_sitting, academic_year, sitting_total_questions,
  questions_presented, questions_correct, questions_not_attempted, percent_correct,
  ks2_subject, conversion_test_year, ks2_max_raw_score, raw_score_equivalent,
  sats_scaled_score, is_below_scaled_range, sitting_finished_at,
  effective_from, effective_to, is_latest, _row_hash, _created_at, _updated_at
) VALUES (
  s.sats_score_id, s.pupil_id, s.subject_id, s.subject_name, s.session_id, s.assessment_id,
  s.year_group_at_sitting, s.academic_year, s.sitting_total_questions,
  s.questions_presented, s.questions_correct, s.questions_not_attempted, s.percent_correct,
  s.ks2_subject, s.conversion_test_year, s.ks2_max_raw_score, s.raw_score_equivalent,
  s.sats_scaled_score, s.is_below_scaled_range, s.sitting_finished_at,
  s.effective_from, s.effective_to, s.is_latest, s._row_hash, run_ts, run_ts
);

SET rows_upserted = @@row_count;

INSERT INTO rebecca_fleming.model_run_log
  (model_name, run_ts, is_full_refresh, change_window_start, input_fingerprint,
   pupils_reprocessed, rows_deleted, rows_upserted)
VALUES
  (this_model, run_ts, is_full, change_window_start, input_fingerprint,
   pupils_reprocessed, rows_deleted, rows_upserted);

COMMIT TRANSACTION;
