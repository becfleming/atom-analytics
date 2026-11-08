-- =============================================================================
-- Load: rebecca_fleming.ref_ks2_scaled_score_conversion
-- =============================================================================
-- Official KS2 raw score -> scaled score conversion tables published by the
-- Standards and Testing Agency on GOV.UK (one page per test year; URL stored on
-- every row). Transcribed from the pages on 2026-11-08 and checked: raw marks
-- contiguous from 0 to max, scaled scores non-decreasing, 80..120.
--
-- Each array below is indexed by raw score (offset 0 = raw 0). NULL means
-- GOV.UK awards no scaled score for that raw mark (below the scoring range).
--
-- Re-runnable: MERGE makes the table exactly match this seed. Adding a new test
-- year = append one STRUCT per subject and re-run. A change here changes the
-- reference fingerprint, which makes the next fct_sats_score_history load a
-- full refresh automatically.
-- =============================================================================

MERGE rebecca_fleming.ref_ks2_scaled_score_conversion AS t
USING (
  SELECT
    seed.test_year,
    seed.ks2_subject,
    raw_score,
    seed.max_raw_score,
    scaled_score,
    seed.source_url
  FROM UNNEST([
    -- 2024 gps: raw 0..70
    STRUCT(2024 AS test_year, 'gps' AS ks2_subject, 70 AS max_raw_score,
           'https://www.gov.uk/government/publications/key-stage-2-tests-2024-scaled-scores/2024-key-stage-2-scaled-score-conversion-tables' AS source_url,
           [NULL, NULL, NULL, 80, 81, 82, 83, 84, 85, 86, 86, 87, 88, 88, 89, 90, 90, 91, 91, 92, 92, 93, 94, 94, 95, 95, 95, 96, 96, 97, 97, 98, 98, 99, 99, 100, 100, 101, 101, 102, 102, 103, 103, 104, 104, 105, 105, 106, 106, 107, 108, 108, 109, 110, 110, 111, 112, 112, 113, 114, 115, 116, 117, 118, 119, 120, 120, 120, 120, 120, 120] AS scaled_score_by_raw),
    -- 2024 maths: raw 0..110
    STRUCT(2024 AS test_year, 'maths' AS ks2_subject, 110 AS max_raw_score,
           'https://www.gov.uk/government/publications/key-stage-2-tests-2024-scaled-scores/2024-key-stage-2-scaled-score-conversion-tables' AS source_url,
           [NULL, NULL, NULL, 81, 82, 83, 84, 84, 85, 86, 86, 87, 87, 88, 88, 89, 89, 90, 90, 90, 91, 91, 91, 92, 92, 92, 93, 93, 93, 94, 94, 94, 94, 95, 95, 95, 96, 96, 96, 96, 96, 97, 97, 97, 97, 98, 98, 98, 98, 99, 99, 99, 99, 99, 100, 100, 100, 100, 101, 101, 101, 101, 101, 102, 102, 102, 102, 103, 103, 103, 103, 103, 104, 104, 104, 104, 105, 105, 105, 105, 106, 106, 106, 106, 107, 107, 107, 108, 108, 108, 109, 109, 109, 110, 110, 111, 111, 111, 112, 112, 113, 114, 114, 115, 116, 117, 118, 119, 120, 120, 120] AS scaled_score_by_raw),
    -- 2024 reading: raw 0..50
    STRUCT(2024 AS test_year, 'reading' AS ks2_subject, 50 AS max_raw_score,
           'https://www.gov.uk/government/publications/key-stage-2-tests-2024-scaled-scores/2024-key-stage-2-scaled-score-conversion-tables' AS source_url,
           [NULL, NULL, NULL, 80, 82, 83, 84, 85, 86, 87, 88, 89, 90, 90, 91, 92, 93, 93, 94, 95, 95, 96, 97, 97, 98, 99, 99, 100, 101, 101, 102, 103, 104, 104, 105, 106, 107, 108, 108, 109, 110, 111, 113, 114, 115, 116, 118, 119, 120, 120, 120] AS scaled_score_by_raw),
    -- 2025 gps: raw 0..70
    STRUCT(2025 AS test_year, 'gps' AS ks2_subject, 70 AS max_raw_score,
           'https://www.gov.uk/government/publications/key-stage-2-tests-2025-scaled-scores/2025-key-stage-2-scaled-score-conversion-tables' AS source_url,
           [NULL, NULL, NULL, 80, 80, 82, 83, 84, 85, 86, 86, 87, 88, 89, 89, 90, 90, 91, 92, 92, 93, 93, 94, 94, 95, 95, 96, 96, 97, 97, 98, 98, 98, 99, 99, 100, 100, 101, 101, 102, 102, 103, 103, 104, 104, 105, 105, 106, 106, 107, 108, 108, 109, 109, 110, 111, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 120, 120, 120, 120, 120] AS scaled_score_by_raw),
    -- 2025 maths: raw 0..110
    STRUCT(2025 AS test_year, 'maths' AS ks2_subject, 110 AS max_raw_score,
           'https://www.gov.uk/government/publications/key-stage-2-tests-2025-scaled-scores/2025-key-stage-2-scaled-score-conversion-tables' AS source_url,
           [NULL, NULL, NULL, 80, 80, 80, 81, 82, 83, 84, 84, 85, 85, 86, 86, 87, 87, 88, 88, 89, 89, 89, 90, 90, 91, 91, 91, 92, 92, 92, 92, 93, 93, 93, 94, 94, 94, 94, 95, 95, 95, 95, 96, 96, 96, 96, 97, 97, 97, 97, 98, 98, 98, 98, 99, 99, 99, 99, 100, 100, 100, 100, 101, 101, 101, 101, 102, 102, 102, 102, 102, 103, 103, 103, 103, 104, 104, 104, 105, 105, 105, 105, 106, 106, 106, 106, 107, 107, 107, 108, 108, 108, 109, 109, 109, 110, 110, 111, 111, 112, 112, 113, 113, 114, 115, 116, 117, 118, 119, 120, 120] AS scaled_score_by_raw),
    -- 2025 reading: raw 0..50
    STRUCT(2025 AS test_year, 'reading' AS ks2_subject, 50 AS max_raw_score,
           'https://www.gov.uk/government/publications/key-stage-2-tests-2025-scaled-scores/2025-key-stage-2-scaled-score-conversion-tables' AS source_url,
           [NULL, NULL, NULL, 80, 80, 82, 83, 84, 85, 86, 87, 88, 89, 89, 90, 91, 92, 92, 93, 94, 95, 95, 96, 97, 97, 98, 99, 99, 100, 101, 101, 102, 103, 104, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 116, 117, 119, 120, 120, 120] AS scaled_score_by_raw),
    -- 2026 gps: raw 0..70
    STRUCT(2026 AS test_year, 'gps' AS ks2_subject, 70 AS max_raw_score,
           'https://www.gov.uk/government/publications/key-stage-2-tests-2026-scaled-scores/2026-key-stage-2-scaled-score-conversion-tables' AS source_url,
           [NULL, NULL, NULL, 80, 81, 82, 83, 84, 85, 86, 87, 87, 88, 89, 90, 90, 91, 91, 92, 92, 93, 94, 94, 95, 95, 95, 96, 96, 97, 97, 98, 98, 99, 99, 100, 100, 100, 101, 101, 102, 102, 103, 103, 104, 104, 105, 105, 106, 106, 107, 107, 108, 108, 109, 109, 110, 111, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 120, 120, 120, 120] AS scaled_score_by_raw),
    -- 2026 maths: raw 0..110
    STRUCT(2026 AS test_year, 'maths' AS ks2_subject, 110 AS max_raw_score,
           'https://www.gov.uk/government/publications/key-stage-2-tests-2026-scaled-scores/2026-key-stage-2-scaled-score-conversion-tables' AS source_url,
           [NULL, NULL, NULL, 80, 80, 80, 80, 81, 82, 83, 83, 84, 85, 85, 86, 86, 87, 87, 88, 88, 89, 89, 90, 90, 90, 91, 91, 92, 92, 92, 93, 93, 93, 94, 94, 94, 94, 95, 95, 95, 96, 96, 96, 96, 97, 97, 97, 97, 98, 98, 98, 98, 99, 99, 99, 99, 100, 100, 100, 100, 101, 101, 101, 101, 101, 102, 102, 102, 102, 103, 103, 103, 103, 104, 104, 104, 104, 105, 105, 105, 106, 106, 106, 106, 107, 107, 107, 108, 108, 108, 108, 109, 109, 109, 110, 110, 111, 111, 112, 112, 113, 113, 114, 114, 115, 116, 117, 118, 119, 120, 120] AS scaled_score_by_raw),
    -- 2026 reading: raw 0..50
    STRUCT(2026 AS test_year, 'reading' AS ks2_subject, 50 AS max_raw_score,
           'https://www.gov.uk/government/publications/key-stage-2-tests-2026-scaled-scores/2026-key-stage-2-scaled-score-conversion-tables' AS source_url,
           [NULL, NULL, NULL, 81, 82, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 93, 94, 95, 95, 96, 97, 98, 98, 99, 99, 100, 101, 101, 102, 103, 103, 104, 105, 106, 106, 107, 108, 109, 109, 110, 111, 112, 113, 114, 116, 117, 118, 120, 120, 120, 120] AS scaled_score_by_raw)
  ]) AS seed,
  UNNEST(seed.scaled_score_by_raw) AS scaled_score WITH OFFSET AS raw_score
) AS s
ON  t.test_year = s.test_year
AND t.ks2_subject = s.ks2_subject
AND t.raw_score = s.raw_score
WHEN MATCHED AND (
     t.max_raw_score != s.max_raw_score
  OR t.scaled_score IS DISTINCT FROM s.scaled_score
  OR t.source_url != s.source_url
) THEN UPDATE SET
  max_raw_score = s.max_raw_score,
  scaled_score  = s.scaled_score,
  source_url    = s.source_url
WHEN NOT MATCHED BY TARGET THEN INSERT
  (test_year, ks2_subject, raw_score, max_raw_score, scaled_score, source_url)
  VALUES
  (s.test_year, s.ks2_subject, s.raw_score, s.max_raw_score, s.scaled_score, s.source_url)
WHEN NOT MATCHED BY SOURCE THEN DELETE;
