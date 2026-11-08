-- =============================================================================
-- Load: rebecca_fleming.int_pupil_subject_session_summary
-- =============================================================================
-- Run on every schedule, after the staging loads.
-- No project is named: the job's default project decides where objects go.
--
-- Incremental by pupil:
--   1. Pupils to reprocess = int_changed_pupils(change window start). The
--      window starts reprocess_overlap_hours before this model's last run, so
--      a staging load that committed late is still picked up.
--   2. Recompute all of their rows with
--      int_pupil_subject_session_summary_as_of(run_ts).
--   3. In one transaction: delete their rows that no longer exist, upsert rows
--      whose content hash changed, and write model_run_log.
--   Full refresh (every pupil) on the first run, when full_refresh = TRUE, or
--   automatically when the definition of the logic functions has changed.
--
-- Re-runnable: rows are only written when their content changes, so a second
-- run with unchanged inputs leaves the table untouched (only a run-log row is
-- added).
-- =============================================================================

DECLARE this_model STRING DEFAULT 'int_pupil_subject_session_summary';
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
-- Watermark and logic check
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

-- Changing the logic of any function this table is computed from forces a full refresh.
SET input_fingerprint = (
  SELECT COALESCE(BIT_XOR(FARM_FINGERPRINT(CONCAT(routine_name, '|', routine_definition))), 0)
  FROM rebecca_fleming.INFORMATION_SCHEMA.ROUTINES
  WHERE routine_name IN (
    'int_pupil_subject_session_summary_as_of',
    'stg_pupils_as_of', 'stg_assessment_sittings_as_of',
    'stg_responses_as_of', 'stg_course_hierarchy_as_of')
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
-- Full refresh: also clear pupils in the table but no longer anywhere in staging.
SELECT pupil_id FROM rebecca_fleming.int_pupil_subject_session_summary WHERE is_full;

SET pupils_reprocessed = (SELECT COUNT(*) FROM affected_pupils);

-- ---------------------------------------------------------------------------
-- 2. Recompute
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE new_rows AS
SELECT
  s.*,
  FARM_FINGERPRINT(TO_JSON_STRING(s)) AS _row_hash
FROM rebecca_fleming.int_pupil_subject_session_summary_as_of(run_ts) AS s
WHERE s.pupil_id IN (SELECT pupil_id FROM affected_pupils);

-- ---------------------------------------------------------------------------
-- 3. Apply
-- ---------------------------------------------------------------------------
BEGIN TRANSACTION;

DELETE FROM rebecca_fleming.int_pupil_subject_session_summary AS t
WHERE t.pupil_id IN (SELECT pupil_id FROM affected_pupils)
  AND NOT EXISTS (SELECT 1 FROM new_rows AS n WHERE n.summary_id = t.summary_id);

SET rows_deleted = @@row_count;

MERGE rebecca_fleming.int_pupil_subject_session_summary AS t
USING new_rows AS s
ON t.summary_id = s.summary_id
WHEN MATCHED AND t._row_hash != s._row_hash THEN UPDATE SET
  pupil_id                     = s.pupil_id,
  subject_id                   = s.subject_id,
  subject_name                 = s.subject_name,
  session_id                   = s.session_id,
  assessment_id                = s.assessment_id,
  session_type                 = s.session_type,
  style                        = s.style,
  year_group_at_sitting        = s.year_group_at_sitting,
  academic_year                = s.academic_year,
  sitting_total_questions      = s.sitting_total_questions,
  sitting_is_complete          = s.sitting_is_complete,
  sitting_is_deleted           = s.sitting_is_deleted,
  pupil_is_deleted             = s.pupil_is_deleted,
  sitting_started_at           = s.sitting_started_at,
  sitting_finished_at          = s.sitting_finished_at,
  questions_presented          = s.questions_presented,
  questions_correct            = s.questions_correct,
  questions_incorrect          = s.questions_incorrect,
  questions_not_attempted      = s.questions_not_attempted,
  superseded_answers           = s.superseded_answers,
  percent_correct              = s.percent_correct,
  percent_correct_of_attempted = s.percent_correct_of_attempted,
  distinct_topics              = s.distinct_topics,
  distinct_subtopics           = s.distinct_subtopics,
  distinct_atoms               = s.distinct_atoms,
  total_seconds_taken          = s.total_seconds_taken,
  avg_seconds_per_question     = s.avg_seconds_per_question,
  first_answered_at            = s.first_answered_at,
  last_answered_at             = s.last_answered_at,
  _row_hash                    = s._row_hash,
  _updated_at                  = run_ts
WHEN NOT MATCHED BY TARGET THEN INSERT (
  summary_id, pupil_id, subject_id, subject_name, session_id, assessment_id,
  session_type, style, year_group_at_sitting, academic_year, sitting_total_questions,
  sitting_is_complete, sitting_is_deleted, pupil_is_deleted,
  sitting_started_at, sitting_finished_at,
  questions_presented, questions_correct, questions_incorrect, questions_not_attempted,
  superseded_answers, percent_correct, percent_correct_of_attempted,
  distinct_topics, distinct_subtopics, distinct_atoms,
  total_seconds_taken, avg_seconds_per_question, first_answered_at, last_answered_at,
  _row_hash, _created_at, _updated_at
) VALUES (
  s.summary_id, s.pupil_id, s.subject_id, s.subject_name, s.session_id, s.assessment_id,
  s.session_type, s.style, s.year_group_at_sitting, s.academic_year, s.sitting_total_questions,
  s.sitting_is_complete, s.sitting_is_deleted, s.pupil_is_deleted,
  s.sitting_started_at, s.sitting_finished_at,
  s.questions_presented, s.questions_correct, s.questions_incorrect, s.questions_not_attempted,
  s.superseded_answers, s.percent_correct, s.percent_correct_of_attempted,
  s.distinct_topics, s.distinct_subtopics, s.distinct_atoms,
  s.total_seconds_taken, s.avg_seconds_per_question, s.first_answered_at, s.last_answered_at,
  s._row_hash, run_ts, run_ts
);

SET rows_upserted = @@row_count;

INSERT INTO rebecca_fleming.model_run_log
  (model_name, run_ts, is_full_refresh, change_window_start, input_fingerprint,
   pupils_reprocessed, rows_deleted, rows_upserted)
VALUES
  (this_model, run_ts, is_full, change_window_start, input_fingerprint,
   pupils_reprocessed, rows_deleted, rows_upserted);

COMMIT TRANSACTION;
