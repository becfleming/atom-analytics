SELECT 'RAW: pupils',COUNT(1) FROM de_raw.pupils UNION ALL 
SELECT 'STG: pupils',COUNT(1) FROM rebecca_fleming.stg_pupils UNION ALL
SELECT 'RAW: course_hierarchy',COUNT(1) FROM de_raw.course_hierarchy UNION ALL 
SELECT 'STG: course_hierarchy',COUNT(1) FROM rebecca_fleming.stg_course_hierarchy UNION ALL
SELECT 'RAW: assessment_sittings',COUNT(1) FROM de_raw.assessment_sittings UNION ALL 
SELECT 'STG: assessment_sittings',COUNT(1) FROM rebecca_fleming.stg_assessment_sittings UNION ALL 
SELECT 'RAW: responses',COUNT(1) FROM de_raw.responses UNION ALL 
SELECT 'STG: responses',COUNT(1) FROM rebecca_fleming.stg_responses;