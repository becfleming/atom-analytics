-- =============================================================================
-- DDL: pupil x subject x session summary
-- =============================================================================
-- General-purpose summary of how each pupil did in each subject in each
-- sitting. Not SATs-specific: every subject and every sitting is included
-- (incomplete, deleted, deleted pupils too), with flags so each consumer can
-- choose its own filters. The SATs model is one consumer.
-- Run on deploy, after the staging DDL.
-- No project is named: the job's default project decides where objects go.
--
-- Objects:
--   int_pupil_subject_session_summary_as_of(ts)  Table function: the logic,
--       computed from staging as loaded at ts (point-in-time recompute).
--   int_pupil_subject_session_summary            Table: the function
--       materialised as of the latest load. Query this for current data.
--
-- Rules
--   * One answer per (pupil, session, question): the latest answer counts for
--     correctness. Earlier answers are counted in superseded_answers and their
--     time is included in total_seconds_taken (it is time the pupil spent).
--   * Only responses that belong to a sitting are included (inner join on
--     pupil_id + session_id); responses to questions with no subject in the
--     hierarchy are excluded, because subject_id is part of the key.
--   * questions_presented = distinct questions with a response row.
--     correct + incorrect + not_attempted = presented.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Logic
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE FUNCTION rebecca_fleming.int_pupil_subject_session_summary_as_of(as_of TIMESTAMP)
OPTIONS (description = 'Summary measures per pupil, subject and session, computed from staging as loaded at as_of')
AS
WITH sittings AS (
  SELECT
    s.pupil_id,
    s.session_id,
    s.assessment_id,
    s.session_type,
    s.style,
    s.year_group_at_sitting,
    s.total_questions,
    s.is_complete,
    s.is_deleted,
    p.is_deleted AS pupil_is_deleted,
    s.started_at,
    s.finished_at
  FROM rebecca_fleming.stg_assessment_sittings_as_of(as_of) AS s
  LEFT JOIN rebecca_fleming.stg_pupils_as_of(as_of) AS p ON p.pupil_id = s.pupil_id
),

responses AS (
  SELECT
    r.pupil_id,
    r.session_id,
    r.question_id,
    r.is_correct,
    r.is_no_attempt,
    r.seconds_taken,
    r.answered_at,
    ROW_NUMBER() OVER (
      PARTITION BY r.pupil_id, r.session_id, r.question_id
      ORDER BY r.answered_at DESC NULLS LAST, r.response_id DESC
    ) AS answer_rank
  FROM rebecca_fleming.stg_responses_as_of(as_of) AS r
  WHERE r.question_id IS NOT NULL
    AND (r.answered_at IS NULL OR r.answered_at <= as_of)
),

hierarchy AS (
  SELECT question_id, subject_id, topic_id, subtopic_id, atom_id
  FROM rebecca_fleming.stg_course_hierarchy_as_of(as_of)
  WHERE subject_id IS NOT NULL
),

subject_names AS (
  SELECT subject_id, MIN(subject_name) AS subject_name
  FROM rebecca_fleming.stg_course_hierarchy_as_of(as_of)
  WHERE subject_id IS NOT NULL
  GROUP BY subject_id
),

aggregated AS (
  SELECT
    s.pupil_id,
    h.subject_id,
    s.session_id,
    s.assessment_id,
    s.session_type,
    s.style,
    s.year_group_at_sitting,
    s.total_questions,
    s.is_complete,
    s.is_deleted,
    s.pupil_is_deleted,
    s.started_at,
    s.finished_at,
    COUNTIF(r.answer_rank = 1)                                                    AS questions_presented,
    COUNTIF(r.answer_rank = 1 AND r.is_correct IS TRUE AND r.is_no_attempt IS NOT TRUE)  AS questions_correct,
    COUNTIF(r.answer_rank = 1 AND r.is_correct IS NOT TRUE AND r.is_no_attempt IS NOT TRUE) AS questions_incorrect,
    COUNTIF(r.answer_rank = 1 AND r.is_no_attempt IS TRUE)                        AS questions_not_attempted,
    COUNTIF(r.answer_rank > 1)                                                    AS superseded_answers,
    COUNT(DISTINCT IF(r.answer_rank = 1, h.topic_id, NULL))                       AS distinct_topics,
    COUNT(DISTINCT IF(r.answer_rank = 1, h.subtopic_id, NULL))                    AS distinct_subtopics,
    COUNT(DISTINCT IF(r.answer_rank = 1, h.atom_id, NULL))                        AS distinct_atoms,
    SUM(r.seconds_taken)                                                          AS total_seconds_taken,
    MIN(r.answered_at)                                                            AS first_answered_at,
    MAX(r.answered_at)                                                            AS last_answered_at
  FROM sittings AS s
  JOIN responses AS r ON r.pupil_id = s.pupil_id AND r.session_id = s.session_id
  JOIN hierarchy AS h ON h.question_id = r.question_id
  GROUP BY s.pupil_id, h.subject_id, s.session_id, s.assessment_id, s.session_type, s.style,
           s.year_group_at_sitting, s.total_questions, s.is_complete, s.is_deleted,
           s.pupil_is_deleted, s.started_at, s.finished_at
)

SELECT
  TO_HEX(SHA256(CONCAT(a.pupil_id, '|', a.subject_id, '|', a.session_id))) AS summary_id,
  a.pupil_id,
  a.subject_id,
  sn.subject_name,
  a.session_id,
  a.assessment_id,
  a.session_type,
  a.style,
  a.year_group_at_sitting,
  EXTRACT(YEAR FROM DATETIME(COALESCE(a.finished_at, a.started_at), 'Europe/London'))
    + IF(EXTRACT(MONTH FROM DATETIME(COALESCE(a.finished_at, a.started_at), 'Europe/London')) >= 9, 1, 0)
                                                     AS academic_year,
  a.total_questions                                  AS sitting_total_questions,
  a.is_complete                                      AS sitting_is_complete,
  a.is_deleted                                       AS sitting_is_deleted,
  a.pupil_is_deleted,
  a.started_at                                       AS sitting_started_at,
  a.finished_at                                      AS sitting_finished_at,
  a.questions_presented,
  a.questions_correct,
  a.questions_incorrect,
  a.questions_not_attempted,
  a.superseded_answers,
  CAST(ROUND(100 * a.questions_correct / a.questions_presented, 2) AS NUMERIC) AS percent_correct,
  CAST(ROUND(100 * SAFE_DIVIDE(a.questions_correct, a.questions_correct + a.questions_incorrect), 2) AS NUMERIC)
                                                     AS percent_correct_of_attempted,
  a.distinct_topics,
  a.distinct_subtopics,
  a.distinct_atoms,
  a.total_seconds_taken,
  CAST(ROUND(SAFE_DIVIDE(a.total_seconds_taken, a.questions_presented), 1) AS NUMERIC) AS avg_seconds_per_question,
  a.first_answered_at,
  a.last_answered_at
FROM aggregated AS a
LEFT JOIN subject_names AS sn ON sn.subject_id = a.subject_id;

-- ---------------------------------------------------------------------------
-- Materialised table (loaded by load/int_pupil_subject_session_summary.sql)
-- Derived from staging, so it can be rebuilt with full_refresh = TRUE.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rebecca_fleming.int_pupil_subject_session_summary (
  summary_id                    STRING    NOT NULL OPTIONS (description = 'Surrogate key: hex SHA-256 of pupil_id|subject_id|session_id. Equals fct_sats_score_history.sats_score_id for the same row'),
  pupil_id                      STRING    NOT NULL,
  subject_id                    STRING    NOT NULL,
  subject_name                  STRING,
  session_id                    STRING    NOT NULL,
  assessment_id                 STRING,
  session_type                  STRING,
  style                         STRING,
  year_group_at_sitting         INT64,
  academic_year                 INT64              OPTIONS (description = 'Academic year (Sept-Aug, Europe/London) of finished_at, else started_at, named by the year it ends (2025 = 2024/25)'),
  sitting_total_questions       INT64              OPTIONS (description = 'total_questions on the sitting (all subjects)'),
  sitting_is_complete           BOOL,
  sitting_is_deleted            BOOL      NOT NULL,
  pupil_is_deleted              BOOL               OPTIONS (description = 'NULL = pupil not found in stg_pupils'),
  sitting_started_at            TIMESTAMP,
  sitting_finished_at           TIMESTAMP,
  questions_presented           INT64     NOT NULL OPTIONS (description = 'Distinct questions in this subject with a response'),
  questions_correct             INT64     NOT NULL,
  questions_incorrect           INT64     NOT NULL OPTIONS (description = 'Attempted and not correct'),
  questions_not_attempted       INT64     NOT NULL,
  superseded_answers            INT64     NOT NULL OPTIONS (description = 'Earlier answers to a question replaced by a later one'),
  percent_correct               NUMERIC(5, 2) NOT NULL OPTIONS (description = '100 * correct / presented'),
  percent_correct_of_attempted  NUMERIC(5, 2)      OPTIONS (description = '100 * correct / (correct + incorrect); NULL if nothing attempted'),
  distinct_topics               INT64     NOT NULL,
  distinct_subtopics            INT64     NOT NULL,
  distinct_atoms                INT64     NOT NULL,
  total_seconds_taken           INT64              OPTIONS (description = 'Sum of seconds_taken over all answers, including superseded ones'),
  avg_seconds_per_question      NUMERIC            OPTIONS (description = 'total_seconds_taken / questions_presented'),
  first_answered_at             TIMESTAMP,
  last_answered_at              TIMESTAMP,
  _row_hash                     INT64     NOT NULL OPTIONS (description = 'Fingerprint of all business columns; rows are only rewritten when it changes'),
  _created_at                   TIMESTAMP NOT NULL,
  _updated_at                   TIMESTAMP NOT NULL,
  PRIMARY KEY (summary_id) NOT ENFORCED
)
PARTITION BY TIMESTAMP_TRUNC(sitting_started_at, MONTH)
CLUSTER BY pupil_id, subject_id, session_id
OPTIONS (description = 'Summary measures per pupil, subject and session (all subjects, all sittings, with status flags). Rebuildable from staging.');
