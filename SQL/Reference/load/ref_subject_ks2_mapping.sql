-- =============================================================================
-- Load: rebecca_fleming.ref_subject_ks2_mapping
-- =============================================================================
-- Makes the table match the subjects currently in stg_course_hierarchy:
--   English -> reading
--   Maths   -> maths
--   everything else (Wellbeing, Science, Screeners, Non-Verbal Reasoning,
--   Verbal Reasoning, and any new subject) -> NULL = not scored
-- Re-runnable: rows are only written when the mapping changes. A change here
-- changes the reference fingerprint, which makes the next
-- fct_sats_score_history load a full refresh automatically.
-- =============================================================================

DECLARE run_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

MERGE rebecca_fleming.ref_subject_ks2_mapping AS t
USING (
  SELECT
    subject_id,
    subject_name,
    CASE subject_name
      WHEN 'English' THEN 'reading'
      WHEN 'Maths'   THEN 'maths'
    END AS ks2_subject
  FROM (
    SELECT subject_id, MIN(subject_name) AS subject_name
    FROM rebecca_fleming.stg_course_hierarchy
    WHERE subject_id IS NOT NULL
    GROUP BY subject_id
  )
) AS s
ON t.subject_id = s.subject_id
WHEN MATCHED AND (
     t.subject_name IS DISTINCT FROM s.subject_name
  OR t.ks2_subject  IS DISTINCT FROM s.ks2_subject
) THEN UPDATE SET
  subject_name     = s.subject_name,
  ks2_subject      = s.ks2_subject,
  _last_updated_at = run_ts
WHEN NOT MATCHED BY TARGET THEN INSERT
  (subject_id, subject_name, ks2_subject, _last_updated_at)
  VALUES
  (s.subject_id, s.subject_name, s.ks2_subject, run_ts)
WHEN NOT MATCHED BY SOURCE THEN DELETE;
