-- =============================================================================
-- DDL: rebecca_fleming.int_changed_pupils(since TIMESTAMP)
-- =============================================================================
-- Pupils whose staged data changed after `since`, for incremental loads of
-- any pupil-grained model. since = NULL returns every pupil ever staged.
-- Run on deploy, after the staging DDL.
-- No project is named: the job's default project decides where objects go.
--
-- A pupil is changed if any of these started or ended a version after since
-- (checking both catches the old pupil when a row moves between pupils):
--   * their pupil row
--   * one of their sittings
--   * one of their responses
--   * the hierarchy of a question they answered (question moved subject,
--     topic or atom, or the subject was renamed)
-- =============================================================================

CREATE OR REPLACE TABLE FUNCTION rebecca_fleming.int_changed_pupils(since TIMESTAMP)
OPTIONS (description = 'Distinct pupil_id whose staged data changed after since; since = NULL returns all pupils')
AS
SELECT DISTINCT pupil_id
FROM (
  SELECT pupil_id
  FROM rebecca_fleming.stg_pupils_history
  WHERE since IS NULL OR _valid_from > since OR _valid_to > since

  UNION ALL
  SELECT pupil_id
  FROM rebecca_fleming.stg_assessment_sittings_history
  WHERE since IS NULL OR _valid_from > since OR _valid_to > since

  UNION ALL
  -- Responses only count through sittings, so on since = NULL the sittings
  -- branch already covers every relevant pupil.
  SELECT pupil_id
  FROM rebecca_fleming.stg_responses_history
  WHERE since IS NOT NULL AND (_valid_from > since OR _valid_to > since)

  UNION ALL
  SELECT r.pupil_id
  FROM rebecca_fleming.stg_responses AS r
  JOIN (
    SELECT DISTINCT question_id
    FROM rebecca_fleming.stg_course_hierarchy_history
    WHERE since IS NOT NULL AND (_valid_from > since OR _valid_to > since)
  ) AS q ON q.question_id = r.question_id
);