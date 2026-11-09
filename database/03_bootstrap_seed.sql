-- =============================================================================
--  GIRISH OPD  |  Hospital Appointment Booking Platform
--  FILE 03 : BOOTSTRAP SEED (small, testable dataset for the API phase)
--  Workspace / schema : NOV_2026_BATCH        DB : Oracle 23ai (APEX 26.1)
-- -----------------------------------------------------------------------------
--  WHY THIS EXISTS
--    The REST API can create patients and generate slots, but it cannot invent
--    departments, doctors or weekly templates. Without at least one of each,
--    /admin/slots/generate returns slots_created = 0 and /availability is empty.
--    This file gives you the minimum to demo the API + Postman today.
--    The full 50+ row seed (12 doctors, 25 patients) comes in the data phase.
--
--  HOW TO RUN
--    SQL Workshop -> SQL Scripts -> Create -> paste -> Run.
--    Plain INSERT/SELECT statements, no "/" needed. Run once.
--    Re-running fails on unique keys (DEPT_CODE, EMP_CODE, EMAIL, PHONE) - that
--    is your cue that the data is already there.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Departments (6)
-- -----------------------------------------------------------------------------
INSERT INTO GIRISH_DEPARTMENTS (DEPT_CODE, DEPT_NAME, FLOOR_NO) VALUES ('CARD',  'Cardiology',        2);
INSERT INTO GIRISH_DEPARTMENTS (DEPT_CODE, DEPT_NAME, FLOOR_NO) VALUES ('NEURO', 'Neurology',         3);
INSERT INTO GIRISH_DEPARTMENTS (DEPT_CODE, DEPT_NAME, FLOOR_NO) VALUES ('PEDIA', 'Pediatrics',        1);
INSERT INTO GIRISH_DEPARTMENTS (DEPT_CODE, DEPT_NAME, FLOOR_NO) VALUES ('ORTHO', 'Orthopedics',       2);
INSERT INTO GIRISH_DEPARTMENTS (DEPT_CODE, DEPT_NAME, FLOOR_NO) VALUES ('DERM',  'Dermatology',       4);
INSERT INTO GIRISH_DEPARTMENTS (DEPT_CODE, DEPT_NAME, FLOOR_NO) VALUES ('GENMED','General Medicine',  1);


-- -----------------------------------------------------------------------------
-- 2. Doctors (4) - dept resolved by code, so no hard-coded ids
-- -----------------------------------------------------------------------------
INSERT INTO GIRISH_DOCTORS (DEPT_ID, EMP_CODE, FULL_NAME, QUALIFICATION, EMAIL,
                            PHONE, ROOM_NO, CONSULT_FEE, LANGUAGES)
SELECT DEPT_ID, 'EMP-1001', 'Dr. Ananya Sharma', 'MD DM Cardiology',
       'ananya.sharma@opd.local', '9845010001', 'C-201', 800, 'English,Hindi,Kannada'
  FROM GIRISH_DEPARTMENTS WHERE DEPT_CODE = 'CARD';

INSERT INTO GIRISH_DOCTORS (DEPT_ID, EMP_CODE, FULL_NAME, QUALIFICATION, EMAIL,
                            PHONE, ROOM_NO, CONSULT_FEE, LANGUAGES)
SELECT DEPT_ID, 'EMP-1002', 'Dr. Vikram Rao', 'MD DM Neurology',
       'vikram.rao@opd.local', '9845010002', 'N-305', 950, 'English,Hindi'
  FROM GIRISH_DEPARTMENTS WHERE DEPT_CODE = 'NEURO';

INSERT INTO GIRISH_DOCTORS (DEPT_ID, EMP_CODE, FULL_NAME, QUALIFICATION, EMAIL,
                            PHONE, ROOM_NO, CONSULT_FEE, LANGUAGES)
SELECT DEPT_ID, 'EMP-1003', 'Dr. Meera Iyer', 'MBBS DCH',
       'meera.iyer@opd.local', '9845010003', 'P-102', 450, 'English,Tamil,Kannada'
  FROM GIRISH_DEPARTMENTS WHERE DEPT_CODE = 'PEDIA';

INSERT INTO GIRISH_DOCTORS (DEPT_ID, EMP_CODE, FULL_NAME, QUALIFICATION, EMAIL,
                            PHONE, ROOM_NO, CONSULT_FEE, LANGUAGES)
SELECT DEPT_ID, 'EMP-1004', 'Dr. Arjun Nair', 'MS Ortho',
       'arjun.nair@opd.local', '9845010004', 'O-210', 700, 'English,Malayalam'
  FROM GIRISH_DEPARTMENTS WHERE DEPT_CODE = 'ORTHO';


-- -----------------------------------------------------------------------------
-- 3. Weekly slot templates
--    DAY_OF_WEEK : 1=Mon .. 5=Fri (1..7 allowed)
--    Generated with a CONNECT BY row generator instead of 5 manual inserts.
-- -----------------------------------------------------------------------------
-- Dr. Sharma : Mon-Fri 09:00-11:00, 15 min, 2 patients per slot
INSERT INTO GIRISH_SLOT_TEMPLATES (DOCTOR_ID, DAY_OF_WEEK, START_TIME, END_TIME,
                                   SLOT_MINUTES, MAX_PATIENTS, EFFECTIVE_FROM)
SELECT d.DOCTOR_ID, w.DAY_NO, '09:00', '11:00', 15, 2, TRUNC(SYSDATE) - 7
  FROM GIRISH_DOCTORS d
 CROSS JOIN (SELECT LEVEL AS DAY_NO FROM dual CONNECT BY LEVEL <= 5) w
 WHERE d.EMP_CODE = 'EMP-1001';

-- Dr. Rao : Mon, Wed, Fri 10:00-12:00, 20 min, 1 patient per slot
INSERT INTO GIRISH_SLOT_TEMPLATES (DOCTOR_ID, DAY_OF_WEEK, START_TIME, END_TIME,
                                   SLOT_MINUTES, MAX_PATIENTS, EFFECTIVE_FROM)
SELECT d.DOCTOR_ID, w.DAY_NO, '10:00', '12:00', 20, 1, TRUNC(SYSDATE) - 7
  FROM GIRISH_DOCTORS d
 CROSS JOIN (SELECT 1 AS DAY_NO FROM dual UNION ALL
             SELECT 3 FROM dual UNION ALL
             SELECT 5 FROM dual) w
 WHERE d.EMP_CODE = 'EMP-1002';

-- Dr. Iyer : Mon-Fri 14:00-16:00, 30 min, 3 patients per slot
INSERT INTO GIRISH_SLOT_TEMPLATES (DOCTOR_ID, DAY_OF_WEEK, START_TIME, END_TIME,
                                   SLOT_MINUTES, MAX_PATIENTS, EFFECTIVE_FROM)
SELECT d.DOCTOR_ID, w.DAY_NO, '14:00', '16:00', 30, 3, TRUNC(SYSDATE) - 7
  FROM GIRISH_DOCTORS d
 CROSS JOIN (SELECT LEVEL AS DAY_NO FROM dual CONNECT BY LEVEL <= 5) w
 WHERE d.EMP_CODE = 'EMP-1003';

-- Dr. Nair : Tue, Thu 11:00-13:00, 15 min, 1 patient per slot
INSERT INTO GIRISH_SLOT_TEMPLATES (DOCTOR_ID, DAY_OF_WEEK, START_TIME, END_TIME,
                                   SLOT_MINUTES, MAX_PATIENTS, EFFECTIVE_FROM)
SELECT d.DOCTOR_ID, w.DAY_NO, '11:00', '13:00', 15, 1, TRUNC(SYSDATE) - 7
  FROM GIRISH_DOCTORS d
 CROSS JOIN (SELECT 2 AS DAY_NO FROM dual UNION ALL
             SELECT 4 FROM dual) w
 WHERE d.EMP_CODE = 'EMP-1004';


-- -----------------------------------------------------------------------------
-- 4. Patients (4)
-- -----------------------------------------------------------------------------
INSERT INTO GIRISH_PATIENTS (UHID, FULL_NAME, DOB, GENDER, PHONE, EMAIL, BLOOD_GROUP)
VALUES ('UHID-1001', 'Ravi Kumar', DATE '1988-04-12', 'M', '9876500001',
        'ravi.kumar@example.com', 'O+');

INSERT INTO GIRISH_PATIENTS (UHID, FULL_NAME, DOB, GENDER, PHONE, EMAIL, BLOOD_GROUP)
VALUES ('UHID-1002', 'Sneha Patil', DATE '1993-11-02', 'F', '9876500002',
        'sneha.patil@example.com', 'A+');

INSERT INTO GIRISH_PATIENTS (UHID, FULL_NAME, DOB, GENDER, PHONE, EMAIL, BLOOD_GROUP)
VALUES ('UHID-1003', 'Aarav Menon', DATE '2016-06-21', 'M', '9876500003',
        NULL, 'B+');

INSERT INTO GIRISH_PATIENTS (UHID, FULL_NAME, DOB, GENDER, PHONE, EMAIL, BLOOD_GROUP)
VALUES ('UHID-1004', 'Fatima Sheikh', DATE '1979-01-30', 'F', '9876500004',
        'fatima.sheikh@example.com', 'AB+');


-- -----------------------------------------------------------------------------
-- 5. Cancellation rules (bands: min <= hours_before < max)
-- -----------------------------------------------------------------------------
INSERT INTO GIRISH_CANCELLATION_RULES (RULE_NAME, MIN_HOURS_BEFORE, MAX_HOURS_BEFORE,
                                       REFUND_PERCENT, PENALTY_AMOUNT)
VALUES ('More than 4 hours before slot', 4, NULL, 100, 0);

INSERT INTO GIRISH_CANCELLATION_RULES (RULE_NAME, MIN_HOURS_BEFORE, MAX_HOURS_BEFORE,
                                       REFUND_PERCENT, PENALTY_AMOUNT)
VALUES ('2 to 4 hours before slot', 2, 4, 50, 0);

INSERT INTO GIRISH_CANCELLATION_RULES (RULE_NAME, MIN_HOURS_BEFORE, MAX_HOURS_BEFORE,
                                       REFUND_PERCENT, PENALTY_AMOUNT)
VALUES ('Less than 2 hours before slot', 0, 2, 0, 100);


-- -----------------------------------------------------------------------------
-- 6. Confirm the bootstrap
-- -----------------------------------------------------------------------------
COMMIT;

SELECT 'departments'  AS object_name, COUNT(*) AS rows_now FROM GIRISH_DEPARTMENTS
UNION ALL SELECT 'doctors',            COUNT(*) FROM GIRISH_DOCTORS
UNION ALL SELECT 'slot_templates',     COUNT(*) FROM GIRISH_SLOT_TEMPLATES
UNION ALL SELECT 'patients',           COUNT(*) FROM GIRISH_PATIENTS
UNION ALL SELECT 'cancellation_rules', COUNT(*) FROM GIRISH_CANCELLATION_RULES;

-- expect: 6 / 4 / 15 / 4 / 3
-- next : POST /admin/slots/generate  {"from_date":"2026-11-09","to_date":"2026-11-22"}
