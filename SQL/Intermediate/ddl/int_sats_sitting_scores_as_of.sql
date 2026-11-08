-- =============================================================================
-- DDL: rebecca_fleming.int_sats_sitting_scores_as_of(as_of TIMESTAMP)
-- =============================================================================
-- THE SATs scoring logic, defined once. Returns one SATs score per
-- (pupil_id, subject_id, session_id), built on
-- int_pupil_subject_session_summary_as_of, from staging as loaded at as_of:
--   * as_of = now  -> used by load/fct_sats_score_history.sql to materialise
--                     the current scores.
--   * as_of = past -> recomputes scores exactly as the model would have
--                     produced them at that time (later corrections are not
--                     visible).
-- Run on deploy, after ddl/int_pupil_subject_session_summary.sql and the
-- ref_* DDL. No project is named: the job's default project decides where
-- objects go.
--
-- Scoring rules
--   1. Qualifying sittings: pupil exists and is not deleted; sitting is
--      complete, not deleted, and finished at or before as_of.
--   2. Per sitting and subject (from the summary): percent = correct /
--      questions presented; no-attempts count as presented, not correct.
--   3. Only subjects with a KS2 test are scored (ref_subject_ks2_mapping:
--      English -> reading, Maths -> maths). Other subjects return no rows.
--   4. Convert with the official GOV.UK table for the academic year of the
--      sitting (Sept-Aug, Europe/London), falling back to the nearest earlier
--      year loaded, or the earliest if the sitting is older than all tables:
--         raw equivalent = FLOOR(correct * max_raw / presented)   (exact integer maths)
--         scaled score   = conversion table at that raw mark
--      GOV.UK gives no scaled score below 3 raw marks; the brief requires 80-120,
--      so those are floored at 80 and flagged is_below_scaled_range.
--   5. Event-time validity: a score is effective from the sitting's
--      finished_at until the pupil's next qualifying sitting in that subject.
--
-- Note: the ref_* tables are current-only, so a past as_of uses today's
-- conversion tables and subject mapping.
-- =============================================================================

CREATE OR REPLACE TABLE FUNCTION rebecca_fleming.int_sats_sitting_scores_as_of(as_of TIMESTAMP)
OPTIONS (description = 'SATs scaled score (80-120) per pupil, subject and sitting, computed from staging as loaded at as_of')
AS
WITH qualifying AS (
  SELECT *
  FROM rebecca_fleming.int_pupil_subject_session_summary_as_of(as_of)
  WHERE pupil_is_deleted IS FALSE
    AND sitting_is_complete IS TRUE
    AND sitting_is_deleted IS FALSE
    AND sitting_finished_at IS NOT NULL
    AND sitting_finished_at <= as_of
),

-- Which conversion year covers which academic years.
conversion_years AS (
  SELECT
    test_year,
    IF(ROW_NUMBER() OVER (ORDER BY test_year) = 1, 0, test_year) AS from_academic_year,
    LEAD(test_year) OVER (ORDER BY test_year)                    AS next_test_year
  FROM (SELECT DISTINCT test_year FROM rebecca_fleming.ref_ks2_scaled_score_conversion)
),

curve_meta AS (
  SELECT
    test_year,
    ks2_subject,
    MAX(max_raw_score)                                  AS max_raw_score,
    MIN(IF(scaled_score IS NOT NULL, raw_score, NULL))  AS min_scored_raw
  FROM rebecca_fleming.ref_ks2_scaled_score_conversion
  GROUP BY test_year, ks2_subject
),

-- Only subjects with a KS2 curve are scored.
mapped AS (
  SELECT
    q.*,
    m.ks2_subject,
    cy.test_year AS conversion_test_year
  FROM qualifying AS q
  JOIN rebecca_fleming.ref_subject_ks2_mapping AS m
    ON m.subject_id = q.subject_id
   AND m.ks2_subject IS NOT NULL
  JOIN conversion_years AS cy
    ON q.academic_year >= cy.from_academic_year
   AND (cy.next_test_year IS NULL OR q.academic_year < cy.next_test_year)
)

SELECT
  mp.pupil_id,
  mp.subject_id,
  mp.subject_name,
  mp.session_id,
  mp.assessment_id,
  mp.year_group_at_sitting,
  mp.sitting_total_questions,
  mp.sitting_finished_at,
  mp.academic_year,
  mp.questions_presented,
  mp.questions_correct,
  mp.questions_not_attempted,
  mp.percent_correct,
  mp.ks2_subject,
  mp.conversion_test_year,
  cm.max_raw_score                     AS ks2_max_raw_score,
  c.raw_score                          AS raw_score_equivalent,
  COALESCE(c.scaled_score, 80)         AS sats_scaled_score,
  c.raw_score < cm.min_scored_raw      AS is_below_scaled_range,
  mp.sitting_finished_at               AS effective_from,
  LEAD(mp.sitting_finished_at) OVER (
    PARTITION BY mp.pupil_id, mp.subject_id
    ORDER BY mp.sitting_finished_at, mp.session_id
  )                                    AS effective_to,
  ROW_NUMBER() OVER (
    PARTITION BY mp.pupil_id, mp.subject_id
    ORDER BY mp.sitting_finished_at DESC, mp.session_id DESC
  ) = 1                                AS is_latest
FROM mapped AS mp
JOIN curve_meta AS cm
  ON cm.test_year = mp.conversion_test_year
 AND cm.ks2_subject = mp.ks2_subject
JOIN rebecca_fleming.ref_ks2_scaled_score_conversion AS c
  ON c.test_year = cm.test_year
 AND c.ks2_subject = cm.ks2_subject
 AND c.raw_score = DIV(mp.questions_correct * cm.max_raw_score, mp.questions_presented);
