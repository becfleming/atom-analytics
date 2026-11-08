WITH sessions_with_responses
AS
(
  SELECT
    assessment_sittings.session_id
  FROM
    de_raw.assessment_sittings
  LEFT JOIN
    de_raw.responses
    ON responses.session_id = assessment_sittings.session_id
  WHERE
    responses.session_id IS NOT NULL
)
SELECT
  pupils.pupil_id,
  COUNT(DISTINCT assessment_sittings.session_id) AS number_of_sittings,
  COUNT(DISTINCT responses.response_id) AS number_of_responses,
  COUNT(DISTINCT sessions_with_responses.session_id) AS number_of_sittings_with_responses 
FROM 
  de_raw.pupils
LEFT JOIN
  de_raw.assessment_sittings
  ON pupils.pupil_id = assessment_sittings.pupil_id
LEFT JOIN
  de_raw.responses
  ON pupils.pupil_id = responses.pupil_id
LEFT JOIN
  sessions_with_responses
  ON sessions_with_responses.session_id = assessment_sittings.session_id
GROUP BY
  pupils.pupil_id;