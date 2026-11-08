-- =============================================================================
-- DDL: rebecca_fleming.model_run_log
-- =============================================================================
-- One row per load run of each model table: audit trail, and the watermark
-- each incremental load reads to find what changed since its last run.
-- Run on deploy. No project is named: the job's default project decides where
-- objects go.
-- =============================================================================

CREATE TABLE IF NOT EXISTS rebecca_fleming.model_run_log (
  model_name           STRING    NOT NULL OPTIONS (description = 'Table loaded, e.g. int_pupil_subject_session_summary'),
  run_ts               TIMESTAMP NOT NULL OPTIONS (description = 'as_of used for the run; the next run reprocesses changes after this (minus an overlap)'),
  is_full_refresh      BOOL      NOT NULL,
  change_window_start  TIMESTAMP          OPTIONS (description = 'Staging changes after this time were reprocessed; NULL on full refresh'),
  input_fingerprint    INT64     NOT NULL OPTIONS (description = 'Fingerprint of the logic (routine definitions) and reference data the model depends on; a change forces a full refresh'),
  pupils_reprocessed   INT64     NOT NULL,
  rows_deleted         INT64     NOT NULL,
  rows_upserted        INT64     NOT NULL,
  PRIMARY KEY (model_name, run_ts) NOT ENFORCED
)
CLUSTER BY model_name
OPTIONS (description = 'One row per load of each rebecca_fleming model table');
