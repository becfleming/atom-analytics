-- =============================================================================
-- DDL: rebecca_fleming.ref_subject_ks2_mapping
-- =============================================================================
-- One row per course subject, giving the KS2 conversion curve used to score
-- it. Only English (-> reading) and Maths (-> maths) have a KS2 test; every
-- other subject has ks2_subject = NULL and gets no SATs score.
-- Populated by load/ref_subject_ks2_mapping.sql.
-- Run on deploy. No project is named: the job's default project decides where
-- objects go.
-- =============================================================================

CREATE TABLE IF NOT EXISTS rebecca_fleming.ref_subject_ks2_mapping (
  subject_id        STRING    NOT NULL OPTIONS (description = 'course_hierarchy.subject_id'),
  subject_name      STRING             OPTIONS (description = 'course_hierarchy.subject_name'),
  ks2_subject       STRING             OPTIONS (description = 'KS2 curve used: maths | reading. NULL = no KS2 test, subject is not scored'),
  _last_updated_at  TIMESTAMP NOT NULL,
  PRIMARY KEY (subject_id) NOT ENFORCED
)
OPTIONS (description = 'Which KS2 conversion curve scores each course subject; NULL = not scored');
