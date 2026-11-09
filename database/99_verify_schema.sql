-- =============================================================================
--  GIRISH OPD  |  Hospital Appointment Booking Platform
--  FILE 99 : SCHEMA VERIFICATION  (read-only, run after FILE 01 + 02)
--  Workspace / schema : NOV_2026_BATCH
--  Run each block separately in SQL Workshop -> SQL Commands, or upload
--  the whole file to SQL Scripts. Nothing here changes data.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. All 10 tables present?  Expected result: 10 rows, STATUS = CREATED
-- -----------------------------------------------------------------------------
WITH expected (table_name) AS (
    SELECT 'GIRISH_DEPARTMENTS'        FROM dual UNION ALL
    SELECT 'GIRISH_DOCTORS'            FROM dual UNION ALL
    SELECT 'GIRISH_SLOT_TEMPLATES'     FROM dual UNION ALL
    SELECT 'GIRISH_SLOTS'              FROM dual UNION ALL
    SELECT 'GIRISH_PATIENTS'           FROM dual UNION ALL
    SELECT 'GIRISH_APPOINTMENTS'       FROM dual UNION ALL
    SELECT 'GIRISH_TOKEN_QUEUE'        FROM dual UNION ALL
    SELECT 'GIRISH_PAYMENTS'           FROM dual UNION ALL
    SELECT 'GIRISH_CANCELLATION_RULES' FROM dual UNION ALL
    SELECT 'GIRISH_ERROR_LOG'          FROM dual
)
SELECT e.table_name,
       CASE WHEN t.table_name IS NULL THEN 'MISSING' ELSE 'CREATED' END AS status,
       c.column_count
FROM expected e
LEFT JOIN user_tables t
       ON t.table_name = e.table_name
LEFT JOIN (SELECT table_name, COUNT(*) AS column_count
             FROM user_tab_columns
            GROUP BY table_name) c
       ON c.table_name = e.table_name
ORDER BY status DESC, e.table_name;

-- -----------------------------------------------------------------------------
-- 2. Constraint inventory per table (expect P, U, R, C types)
-- -----------------------------------------------------------------------------
SELECT table_name, constraint_type, COUNT(*) AS how_many
FROM user_constraints
WHERE table_name LIKE 'GIRISH\_%' ESCAPE '\'
GROUP BY table_name, constraint_type
ORDER BY table_name, constraint_type;

-- -----------------------------------------------------------------------------
-- 3. Foreign keys with their delete action (RESTRICT / CASCADE / SET NULL)
-- -----------------------------------------------------------------------------
SELECT c.table_name            AS child_table,
       c.constraint_name,
       c.delete_rule,
       p.table_name            AS parent_table
FROM user_constraints c
JOIN user_constraints p
  ON p.constraint_name = c.r_constraint_name
WHERE c.constraint_type = 'R'
  AND c.table_name LIKE 'GIRISH\_%' ESCAPE '\'
ORDER BY c.table_name;

-- -----------------------------------------------------------------------------
-- 4. Indexes
-- -----------------------------------------------------------------------------
SELECT table_name, index_name, uniqueness, status
FROM user_indexes
WHERE table_name LIKE 'GIRISH\_%' ESCAPE '\'
ORDER BY table_name, index_name;

-- -----------------------------------------------------------------------------
-- 5. Sequence + triggers + identity columns
-- -----------------------------------------------------------------------------
SELECT sequence_name, last_number, increment_by, cache_size
FROM user_sequences
WHERE sequence_name = 'SEQ_GIRISH_BOOKING_REF';

SELECT trigger_name, table_name, status, trigger_type
FROM user_triggers
WHERE trigger_name LIKE 'TRG\_GIRISH\_%' ESCAPE '\'
ORDER BY trigger_name;

SELECT table_name, column_name, generation_type
FROM user_tab_identity_cols
ORDER BY table_name;

-- -----------------------------------------------------------------------------
-- 6. Row counts (all should be 0 until seed data is loaded)
-- -----------------------------------------------------------------------------
SELECT 'GIRISH_DEPARTMENTS'        AS table_name, COUNT(*) AS rows_now FROM GIRISH_DEPARTMENTS
UNION ALL SELECT 'GIRISH_DOCTORS',            COUNT(*) FROM GIRISH_DOCTORS
UNION ALL SELECT 'GIRISH_SLOT_TEMPLATES',     COUNT(*) FROM GIRISH_SLOT_TEMPLATES
UNION ALL SELECT 'GIRISH_SLOTS',              COUNT(*) FROM GIRISH_SLOTS
UNION ALL SELECT 'GIRISH_PATIENTS',           COUNT(*) FROM GIRISH_PATIENTS
UNION ALL SELECT 'GIRISH_APPOINTMENTS',       COUNT(*) FROM GIRISH_APPOINTMENTS
UNION ALL SELECT 'GIRISH_TOKEN_QUEUE',        COUNT(*) FROM GIRISH_TOKEN_QUEUE
UNION ALL SELECT 'GIRISH_PAYMENTS',           COUNT(*) FROM GIRISH_PAYMENTS
UNION ALL SELECT 'GIRISH_CANCELLATION_RULES', COUNT(*) FROM GIRISH_CANCELLATION_RULES
UNION ALL SELECT 'GIRISH_ERROR_LOG',          COUNT(*) FROM GIRISH_ERROR_LOG
ORDER BY table_name;

-- -----------------------------------------------------------------------------
-- 7. OPTIONAL negative tests - run ONE at a time, every one SHOULD fail.
--    Uncomment a line, run it, confirm the ORA error, then re-comment it.
--    This proves the constraints actually bite (good screenshot for the report).
-- -----------------------------------------------------------------------------
-- expect ORA-02290 CK_GIRISH_PAT_GENDER
-- INSERT INTO GIRISH_PATIENTS (UHID, FULL_NAME, GENDER, PHONE)
-- VALUES ('TEST-01', 'Bad Gender', 'X', '9000000001');

-- expect ORA-02290 CK_GIRISH_SLOT_STATUS
-- INSERT INTO GIRISH_SLOTS (DOCTOR_ID, SLOT_DATE, START_TIME, END_TIME)
-- VALUES (1, DATE '2026-11-20', '09:00', '09:15');   -- run only AFTER a doctor exists

-- expect ORA-02290 CK_GIRISH_SLOT_CAPACITY  (booked > capacity)
-- UPDATE GIRISH_SLOTS SET CURRENT_BOOKINGS = 5, MAX_CAPACITY = 2 WHERE SLOT_ID = 1;

-- expect ORA-00001 UK_GIRISH_DEPT_CODE  (run twice)
-- INSERT INTO GIRISH_DEPARTMENTS (DEPT_CODE, DEPT_NAME) VALUES ('CARD', 'Cardiology');

-- expect ORA-01400 cannot insert NULL (NOT NULL columns are enforced)
-- INSERT INTO GIRISH_DOCTORS (DEPT_ID, EMP_CODE, FULL_NAME, EMAIL, CONSULT_FEE)
-- VALUES (1, 'EMPX', 'No Email', NULL, 500);
