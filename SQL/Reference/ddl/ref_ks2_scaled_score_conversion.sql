-- =============================================================================
-- DDL: rebecca_fleming.ref_ks2_scaled_score_conversion
-- =============================================================================
-- Official KS2 raw score -> scaled score conversion, one row per
-- (test_year, ks2_subject, raw_score). Populated by
-- load/ref_ks2_scaled_score_conversion.sql from the GOV.UK tables.
-- Run on deploy. No project is named: the job's default project decides where
-- objects go.
-- =============================================================================

CREATE TABLE IF NOT EXISTS rebecca_fleming.ref_ks2_scaled_score_conversion (
  test_year      INT64  NOT NULL OPTIONS (description = 'Calendar year of the summer the test was sat; equals the academic year it ends (2025 = 2024/25)'),
  ks2_subject    STRING NOT NULL OPTIONS (description = 'maths | reading | gps (English grammar, punctuation and spelling)'),
  raw_score      INT64  NOT NULL OPTIONS (description = 'Raw test mark, 0..max_raw_score'),
  max_raw_score  INT64  NOT NULL OPTIONS (description = 'Maximum raw mark of the test (maths 110, reading 50, gps 70)'),
  scaled_score   INT64           OPTIONS (description = 'Scaled score 80..120. NULL = no scaled score awarded (below the scoring range)'),
  source_url     STRING NOT NULL OPTIONS (description = 'GOV.UK page the row was transcribed from'),
  PRIMARY KEY (test_year, ks2_subject, raw_score) NOT ENFORCED
)
CLUSTER BY test_year, ks2_subject
OPTIONS (description = 'Official KS2 raw-to-scaled score conversion tables (Standards and Testing Agency, GOV.UK)');
