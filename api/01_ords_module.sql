-- =============================================================================
--  GIRISH OPD  |  Hospital Appointment Booking Platform
--  FILE : ORDS REST MODULE  (Phase 3 - expose the database as an API)
--  Workspace / schema : NOV_2026_BATCH        DB : Oracle 23ai (APEX 26.1)
--  Module : girish.opd.api      Base path : girish/opd/v1/
-- -----------------------------------------------------------------------------
--  HOW TO RUN
--    SQL Workshop -> SQL Scripts -> Create -> paste -> Run in Background
--    Expect: "1 Statement Processed, 1 Successful" (the whole file is ONE
--    PL/SQL block, terminated by "/" - same rule as the trigger script).
--
--  WHERE IS MY URL?
--    SQL Workshop -> RESTful Services -> girish.opd.api
--    The module page shows the full base URL, normally
--        https://<adb-host>/ords/<schema>/girish/opd/v1/
--    Handlers can be tested right there with the "Test" / "Open in browser"
--    button, before touching Postman.
--
--  NOTE ON LOGIC
--    The PL/SQL package (GIRISH_OPD_PKG) does not exist yet, so these handlers
--    contain the booking logic inline. When the package is built, each handler
--    shrinks to a single call - the endpoints and JSON stay identical.
--
--  ENDPOINTS
--    GET  ping                              health check
--    GET  departments                       departments + doctor counts
--    GET  doctors?dept_id=&q=               search doctors
--    GET  availability?doc_id=&date=        free slots + remaining seats
--    POST patients                          add a patient (dummy data entry)
--    POST admin/slots/generate              generate slots from weekly templates
--    POST appointments                      hold a slot (5 min, 201 Created)
--    POST appointments/confirm              confirm hold + simulated payment
--    GET  appointments/:reference           appointment, doctor, room, token
--    PUT  appointments/cancel               cancel with rule-based refund
--    GET  admin/appointments?status=&date=&doctor_id=
--    POST admin/departments     add a department (dummy data via Postman)
--    POST admin/doctors         add a doctor  (dummy data via Postman)
--    POST admin/templates       add weekly slots (or all_weekdays=true)
--    GET  templates?doctor_id=  check the weekly plan
-- =============================================================================
DECLARE
    c_mod CONSTANT VARCHAR2(40) := 'girish.opd.api';
BEGIN

    ---------------------------------------------------------------------------
    -- 0. clean rebuild: drop the module if it already exists
    ---------------------------------------------------------------------------
    BEGIN
        ORDS.DELETE_MODULE(p_module_name => c_mod);
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END;

    ---------------------------------------------------------------------------
    -- 1. module
    ---------------------------------------------------------------------------
    ORDS.DEFINE_MODULE(
        p_module_name    => c_mod,
        p_base_path      => 'girish/opd/v1/',
        p_items_per_page => 50,
        p_status         => 'PUBLISHED',
        p_comments       => 'Hospital OPD appointment booking API');

    ---------------------------------------------------------------------------
    -- 2. GET ping   ->  {"status":"ok", "server_time":"..."}
    ---------------------------------------------------------------------------
    ORDS.DEFINE_TEMPLATE(p_module_name => c_mod, p_pattern => 'ping');

    ORDS.DEFINE_HANDLER(
        p_module_name => c_mod,
        p_pattern     => 'ping',
        p_method      => 'GET',
        p_source_type => 'json/item',
        p_source      => q'[
            SELECT 'ok' AS status,
                   TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') AS server_time,
                   USER AS db_user
              FROM dual
        ]');

    ---------------------------------------------------------------------------
    -- 3. GET departments   (LEFT OUTER JOIN + GROUP BY -> doctor count)
    ---------------------------------------------------------------------------
    ORDS.DEFINE_TEMPLATE(p_module_name => c_mod, p_pattern => 'departments/');

    ORDS.DEFINE_HANDLER(
        p_module_name    => c_mod,
        p_pattern        => 'departments/',
        p_method         => 'GET',
        p_source_type    => 'json/collection',
        p_items_per_page => 50,
        p_source         => q'[
            SELECT dp.dept_id,
                   dp.dept_code,
                   dp.dept_name,
                   dp.floor_no,
                   COUNT(d.doctor_id) AS doctor_count,
                   MIN(d.consult_fee) AS min_fee,
                   MAX(d.consult_fee) AS max_fee
              FROM girish_departments dp
              LEFT OUTER JOIN girish_doctors d
                   ON d.dept_id  = dp.dept_id
                  AND d.is_active = 'Y'
             WHERE dp.is_active = 'Y'
             GROUP BY dp.dept_id, dp.dept_code, dp.dept_name, dp.floor_no
             ORDER BY dp.dept_name
        ]');

    ---------------------------------------------------------------------------
    -- 4. GET doctors?dept_id=&q=
    ---------------------------------------------------------------------------
    ORDS.DEFINE_TEMPLATE(p_module_name => c_mod, p_pattern => 'doctors/');

    ORDS.DEFINE_PARAMETER(
        p_module_name => c_mod, p_pattern => 'doctors/', p_method => 'GET',
        p_name => 'dept_id', p_bind_variable_name => 'dept_id',
        p_source_type => 'QUERY', p_param_type => 'STRING',
        p_access_method => 'IN', p_comments => 'filter by department');

    ORDS.DEFINE_PARAMETER(
        p_module_name => c_mod, p_pattern => 'doctors/', p_method => 'GET',
        p_name => 'q', p_bind_variable_name => 'q',
        p_source_type => 'QUERY', p_param_type => 'STRING',
        p_access_method => 'IN', p_comments => 'search by doctor name');

    ORDS.DEFINE_HANDLER(
        p_module_name    => c_mod,
        p_pattern        => 'doctors/',
        p_method         => 'GET',
        p_source_type    => 'json/collection',
        p_items_per_page => 50,
        p_source         => q'[
            SELECT d.doctor_id,
                   d.emp_code,
                   d.full_name,
                   d.qualification,
                   d.email,
                   d.phone,
                   d.room_no,
                   d.consult_fee,
                   d.languages,
                   dp.dept_id,
                   dp.dept_name,
                   (SELECT COUNT(*)
                      FROM girish_slot_templates t
                     WHERE t.doctor_id = d.doctor_id
                       AND t.is_active = 'Y') AS weekly_sessions
              FROM girish_doctors d
              JOIN girish_departments dp ON dp.dept_id = d.dept_id
             WHERE d.is_active = 'Y'
               AND (:dept_id IS NULL OR d.dept_id = TO_NUMBER(:dept_id))
               AND (:q IS NULL OR UPPER(d.full_name) LIKE '%' || UPPER(:q) || '%')
             ORDER BY d.full_name
        ]');

    ---------------------------------------------------------------------------
    -- 5. GET availability?doc_id=&date=YYYY-MM-DD
    ---------------------------------------------------------------------------
    ORDS.DEFINE_TEMPLATE(p_module_name => c_mod, p_pattern => 'availability/');

    ORDS.DEFINE_PARAMETER(
        p_module_name => c_mod, p_pattern => 'availability/', p_method => 'GET',
        p_name => 'doc_id', p_bind_variable_name => 'doc_id',
        p_source_type => 'QUERY', p_param_type => 'STRING',
        p_access_method => 'IN', p_comments => 'doctor id');

    ORDS.DEFINE_PARAMETER(
        p_module_name => c_mod, p_pattern => 'availability/', p_method => 'GET',
        p_name => 'date', p_bind_variable_name => 'date',
        p_source_type => 'QUERY', p_param_type => 'STRING',
        p_access_method => 'IN', p_comments => 'slot date YYYY-MM-DD');

    ORDS.DEFINE_HANDLER(
        p_module_name    => c_mod,
        p_pattern        => 'availability/',
        p_method         => 'GET',
        p_source_type    => 'json/collection',
        p_items_per_page => 200,
        p_source         => q'[
            SELECT s.slot_id,
                   TO_CHAR(s.slot_date,'YYYY-MM-DD') AS slot_date,
                   s.start_time,
                   s.end_time,
                   s.max_capacity,
                   s.current_bookings,
                   (s.max_capacity - s.current_bookings) AS seats_left,
                   d.doctor_id,
                   d.full_name AS doctor_name,
                   d.room_no,
                   d.consult_fee
              FROM girish_slots s
              JOIN girish_doctors d ON d.doctor_id = s.doctor_id
             WHERE s.status = 'AVAILABLE'
               AND s.current_bookings < s.max_capacity
               AND (:doc_id IS NULL OR d.doctor_id = TO_NUMBER(:doc_id))
               AND s.slot_date = NVL(TO_DATE(:date,'YYYY-MM-DD'), TRUNC(SYSDATE))
             ORDER BY d.full_name, s.start_time
        ]');

    ---------------------------------------------------------------------------
    -- 6. POST patients    body: {"uhid","full_name","gender","phone",...}
    ---------------------------------------------------------------------------
    ORDS.DEFINE_TEMPLATE(p_module_name => c_mod, p_pattern => 'patients/');

    ORDS.DEFINE_HANDLER(
        p_module_name => c_mod,
        p_pattern     => 'patients/',
        p_method      => 'POST',
        p_source_type => 'plsql/block',
        p_source      => q'[
DECLARE
    l_uhid   girish_patients.uhid%TYPE        := JSON_VALUE(:body, '$.uhid');
    l_name   girish_patients.full_name%TYPE   := JSON_VALUE(:body, '$.full_name');
    l_gender girish_patients.gender%TYPE      := UPPER(JSON_VALUE(:body, '$.gender'));
    l_phone  girish_patients.phone%TYPE       := JSON_VALUE(:body, '$.phone');
    l_email  girish_patients.email%TYPE       := JSON_VALUE(:body, '$.email');
    l_blood  girish_patients.blood_group%TYPE := UPPER(JSON_VALUE(:body, '$.blood_group'));
    l_dob    DATE                             := TO_DATE(JSON_VALUE(:body, '$.dob'), 'YYYY-MM-DD');
    l_id     NUMBER;
BEGIN
    IF l_uhid IS NULL OR l_name IS NULL OR l_phone IS NULL OR l_gender IS NULL THEN
        :status := 400;
        :body   := '{"status":"BAD_REQUEST","message":"uhid, full_name, gender and phone are required"}';
        RETURN;
    END IF;

    INSERT INTO girish_patients (uhid, full_name, dob, gender, phone, email, blood_group)
    VALUES (l_uhid, l_name, l_dob, l_gender, l_phone, l_email, l_blood)
    RETURNING patient_id INTO l_id;

    COMMIT;
    :status := 201;
    :body   := JSON_OBJECT('status'     VALUE 'CREATED',
                           'patient_id' VALUE l_id,
                           'uhid'       VALUE l_uhid,
                           'full_name'  VALUE l_name RETURNING CLOB);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DECLARE
            PRAGMA AUTONOMOUS_TRANSACTION;
        BEGIN
            INSERT INTO girish_error_log (module_name, error_code, error_message)
            VALUES ('ORDS POST patients', TO_CHAR(SQLCODE), SUBSTR(SQLERRM,1,4000));
            COMMIT;
        END;
        :status := CASE WHEN SQLCODE = -1 THEN 409 ELSE 500 END;
        :body   := JSON_OBJECT('status'  VALUE 'ERROR',
                               'message' VALUE SUBSTR(SQLERRM,1,400) RETURNING CLOB);
END;
        ]');

    ---------------------------------------------------------------------------
    -- 7. POST admin/slots/generate
    --    body: {"doctor_id":1,"from_date":"2026-11-10","to_date":"2026-11-30"}
    --    Turns weekly templates into dated slots (idempotent: existing slots
    --    are skipped, so it is safe to run repeatedly).
    ---------------------------------------------------------------------------
    ORDS.DEFINE_TEMPLATE(p_module_name => c_mod, p_pattern => 'admin/slots/generate');

    ORDS.DEFINE_HANDLER(
        p_module_name => c_mod,
        p_pattern     => 'admin/slots/generate',
        p_method      => 'POST',
        p_source_type => 'plsql/block',
        p_source      => q'[
DECLARE
    l_doc  NUMBER := TO_NUMBER(JSON_VALUE(:body, '$.doctor_id'));
    l_from DATE   := NVL(TO_DATE(JSON_VALUE(:body, '$.from_date'), 'YYYY-MM-DD'), TRUNC(SYSDATE));
    l_to   DATE   := NVL(TO_DATE(JSON_VALUE(:body, '$.to_date'),   'YYYY-MM-DD'), TRUNC(SYSDATE) + 30);
    l_cnt  NUMBER := 0;
BEGIN
    IF l_to < l_from THEN
        :status := 400;
        :body   := '{"status":"BAD_REQUEST","message":"to_date must be on or after from_date"}';
        RETURN;
    END IF;

    INSERT INTO girish_slots (doctor_id, template_id, slot_date, start_time, end_time,
                              max_capacity, current_bookings, status)
    SELECT g.doctor_id, g.template_id, g.slot_date, g.start_time, g.end_time,
           g.max_patients, 0, 'AVAILABLE'
      FROM (
            SELECT t.doctor_id,
                   t.template_id,
                   dt.slot_date,
                   TO_CHAR(TO_DATE(t.start_time,'HH24:MI')
                           + (l.lvl - 1) * t.slot_minutes / 1440, 'HH24:MI') AS start_time,
                   TO_CHAR(TO_DATE(t.start_time,'HH24:MI')
                           + l.lvl * t.slot_minutes / 1440, 'HH24:MI')       AS end_time,
                   t.max_patients
              FROM girish_slot_templates t
             CROSS JOIN (
                    SELECT l_from + LEVEL - 1 AS slot_date
                      FROM dual
                   CONNECT BY LEVEL <= (l_to - l_from + 1)
                   ) dt
             CROSS JOIN (
                    SELECT LEVEL AS lvl
                      FROM dual
                   CONNECT BY LEVEL <= 96
                   ) l
             WHERE t.is_active = 'Y'
               AND (l_doc IS NULL OR t.doctor_id = l_doc)
               -- 1=Monday .. 7=Sunday, independent of NLS settings
               AND t.day_of_week = TRUNC(dt.slot_date) - TRUNC(dt.slot_date,'IW') + 1
               AND t.effective_from <= dt.slot_date
               AND (t.effective_to IS NULL OR t.effective_to >= dt.slot_date)
               AND l.lvl <= (TO_DATE(t.end_time,'HH24:MI') - TO_DATE(t.start_time,'HH24:MI'))
                            * 24 * 60 / t.slot_minutes
           ) g
     WHERE NOT EXISTS (
            SELECT 1
              FROM girish_slots s
             WHERE s.doctor_id  = g.doctor_id
               AND s.slot_date  = g.slot_date
               AND s.start_time = g.start_time);

    l_cnt := SQL%ROWCOUNT;
    COMMIT;
    :status := 201;
    :body   := JSON_OBJECT('status'        VALUE 'GENERATED',
                           'slots_created' VALUE l_cnt,
                           'from_date'     VALUE TO_CHAR(l_from,'YYYY-MM-DD'),
                           'to_date'       VALUE TO_CHAR(l_to,'YYYY-MM-DD') RETURNING CLOB);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DECLARE
            PRAGMA AUTONOMOUS_TRANSACTION;
        BEGIN
            INSERT INTO girish_error_log (module_name, error_code, error_message)
            VALUES ('ORDS generate slots', TO_CHAR(SQLCODE), SUBSTR(SQLERRM,1,4000));
            COMMIT;
        END;
        :status := 500;
        :body   := JSON_OBJECT('status'  VALUE 'ERROR',
                               'message' VALUE SUBSTR(SQLERRM,1,400) RETURNING CLOB);
END;
        ]');

    ---------------------------------------------------------------------------
    -- 8. POST appointments   (hold a slot, 5-minute TTL)
    --    body: {"slot_id":1,"patient_id":1}
    --    Concurrency: SELECT ... FOR UPDATE on the slot row + capacity check
    --    inside the same transaction -> the second concurrent caller gets 409.
    ---------------------------------------------------------------------------
    ORDS.DEFINE_TEMPLATE(p_module_name => c_mod, p_pattern => 'appointments/');

    ORDS.DEFINE_HANDLER(
        p_module_name => c_mod,
        p_pattern     => 'appointments/',
        p_method      => 'POST',
        p_source_type => 'plsql/block',
        p_source      => q'[
DECLARE
    l_slot_id  NUMBER := TO_NUMBER(JSON_VALUE(:body, '$.slot_id'));
    l_patient  NUMBER := TO_NUMBER(JSON_VALUE(:body, '$.patient_id'));
    l_cap      NUMBER;
    l_booked   NUMBER;
    l_status   girish_slots.status%TYPE;
    l_fee      NUMBER;
    l_cnt      NUMBER;
    l_ref      VARCHAR2(20);
    l_appt_id  NUMBER;
BEGIN
    IF l_slot_id IS NULL OR l_patient IS NULL THEN
        :status := 400;
        :body   := '{"status":"BAD_REQUEST","message":"slot_id and patient_id are required"}';
        RETURN;
    END IF;

    -- patient must exist and be active
    SELECT COUNT(*) INTO l_cnt
      FROM girish_patients
     WHERE patient_id = l_patient AND is_active = 'Y';
    IF l_cnt = 0 THEN
        :status := 404;
        :body   := '{"status":"NOT_FOUND","message":"Patient not found"}';
        RETURN;
    END IF;

    -- PESSIMISTIC LOCK: one booker at a time on this slot row
    BEGIN
        SELECT max_capacity, current_bookings, status
          INTO l_cap, l_booked, l_status
          FROM girish_slots
         WHERE slot_id = l_slot_id
           FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            :status := 404;
            :body   := '{"status":"NOT_FOUND","message":"Slot not found"}';
            RETURN;
    END;

    IF l_status <> 'AVAILABLE' OR l_booked >= l_cap THEN
        ROLLBACK;
        :status := 409;
        :body   := JSON_OBJECT('status'  VALUE 'CONFLICT',
                               'message' VALUE 'Slot is fully booked',
                               'slot_id' VALUE l_slot_id RETURNING CLOB);
        RETURN;
    END IF;

    SELECT d.consult_fee INTO l_fee
      FROM girish_slots s
      JOIN girish_doctors d ON d.doctor_id = s.doctor_id
     WHERE s.slot_id = l_slot_id;

    l_ref := 'OPD-' || TO_CHAR(SYSDATE,'YYYYMM') || '-' ||
             LPAD(SEQ_GIRISH_BOOKING_REF.NEXTVAL, 5, '0');

    INSERT INTO girish_appointments
           (booking_ref, slot_id, patient_id, status, consult_fee,
            hold_expires_at, booked_at)
    VALUES (l_ref, l_slot_id, l_patient, 'HELD', l_fee,
            SYSTIMESTAMP + INTERVAL '5' MINUTE, SYSTIMESTAMP)
    RETURNING appointment_id INTO l_appt_id;

    -- reserve the seat; capacity counter is the single source of truth
    UPDATE girish_slots
       SET current_bookings = current_bookings + 1,
           status = CASE WHEN current_bookings + 1 >= max_capacity
                         THEN 'BOOKED' ELSE 'AVAILABLE' END
     WHERE slot_id = l_slot_id;

    COMMIT;
    :status := 201;
    :body   := JSON_OBJECT('status'          VALUE 'HELD',
                           'reference'       VALUE l_ref,
                           'appointment_id'  VALUE l_appt_id,
                           'slot_id'         VALUE l_slot_id,
                           'consult_fee'     VALUE l_fee,
                           'hold_expires_in'=> '5 minutes' RETURNING CLOB);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DECLARE
            PRAGMA AUTONOMOUS_TRANSACTION;
        BEGIN
            INSERT INTO girish_error_log (module_name, error_code, error_message)
            VALUES ('ORDS POST appointments', TO_CHAR(SQLCODE), SUBSTR(SQLERRM,1,4000));
            COMMIT;
        END;
        :status := 500;
        :body   := JSON_OBJECT('status'  VALUE 'ERROR',
                               'message' VALUE SUBSTR(SQLERRM,1,400) RETURNING CLOB);
END;
        ]');

    ---------------------------------------------------------------------------
    -- 9. POST appointments/confirm   body: {"reference":"OPD-...","payment_mode":"UPI"}
    ---------------------------------------------------------------------------
    ORDS.DEFINE_TEMPLATE(p_module_name => c_mod, p_pattern => 'appointments/confirm');

    ORDS.DEFINE_HANDLER(
        p_module_name => c_mod,
        p_pattern     => 'appointments/confirm',
        p_method      => 'POST',
        p_source_type => 'plsql/block',
        p_source      => q'[
DECLARE
    l_ref     VARCHAR2(20) := JSON_VALUE(:body, '$.reference');
    l_mode    VARCHAR2(10) := UPPER(NVL(JSON_VALUE(:body, '$.payment_mode'), 'CASH'));
    l_status  girish_appointments.status%TYPE;
    l_expires TIMESTAMP(6);
    l_fee     NUMBER;
    l_appt_id NUMBER;
    l_txn     VARCHAR2(40);
BEGIN
    IF l_ref IS NULL THEN
        :status := 400;
        :body   := '{"status":"BAD_REQUEST","message":"reference is required"}';
        RETURN;
    END IF;

    IF l_mode NOT IN ('UPI','CARD','CASH','NETBANKING','WALLET') THEN
        :status := 400;
        :body   := '{"status":"BAD_REQUEST","message":"payment_mode must be UPI, CARD, CASH, NETBANKING or WALLET"}';
        RETURN;
    END IF;

    BEGIN
        SELECT appointment_id, status, hold_expires_at, consult_fee
          INTO l_appt_id, l_status, l_expires, l_fee
          FROM girish_appointments
         WHERE booking_ref = l_ref
           FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            :status := 404;
            :body   := '{"status":"NOT_FOUND","message":"Booking reference not found"}';
            RETURN;
    END;

    IF l_status <> 'HELD' THEN
        ROLLBACK;
        :status := 409;
        :body   := JSON_OBJECT('status'  VALUE 'CONFLICT',
                               'message' VALUE 'Only a HELD booking can be confirmed',
                               'current_status' VALUE l_status RETURNING CLOB);
        RETURN;
    END IF;

    IF l_expires IS NOT NULL AND l_expires < SYSTIMESTAMP THEN
        ROLLBACK;
        :status := 409;
        :body   := JSON_OBJECT('status'  VALUE 'CONFLICT',
                               'message' VALUE 'Hold has expired, please book again',
                               'reference' VALUE l_ref RETURNING CLOB);
        RETURN;
    END IF;

    UPDATE girish_appointments
       SET status          = 'CONFIRMED',
           confirmed_at    = SYSTIMESTAMP,
           hold_expires_at = NULL
     WHERE appointment_id = l_appt_id;

    l_txn := 'TXN-' || TO_CHAR(SYSTIMESTAMP,'YYYYMMDDHH24MISS') || '-' || l_appt_id;

    INSERT INTO girish_payments (appointment_id, entry_type, payment_mode,
                                 txn_ref, amount, status)
    VALUES (l_appt_id, 'CHARGE', l_mode, l_txn, l_fee, 'SUCCESS');

    COMMIT;
    :status := 200;
    :body   := JSON_OBJECT('status'       VALUE 'CONFIRMED',
                           'reference'    VALUE l_ref,
                           'payment_mode' VALUE l_mode,
                           'amount'       VALUE l_fee,
                           'txn_ref'      VALUE l_txn RETURNING CLOB);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DECLARE
            PRAGMA AUTONOMOUS_TRANSACTION;
        BEGIN
            INSERT INTO girish_error_log (module_name, error_code, error_message)
            VALUES ('ORDS confirm appointment', TO_CHAR(SQLCODE), SUBSTR(SQLERRM,1,4000));
            COMMIT;
        END;
        :status := 500;
        :body   := JSON_OBJECT('status'  VALUE 'ERROR',
                               'message' VALUE SUBSTR(SQLERRM,1,400) RETURNING CLOB);
END;
        ]');

    ---------------------------------------------------------------------------
    -- 10. GET appointments/:reference
    --     INNER JOIN chain for doctor/room/dept + LEFT JOIN for the token
    --     (a token only exists after check-in). 404 when the ref is unknown.
    ---------------------------------------------------------------------------
    ORDS.DEFINE_TEMPLATE(p_module_name => c_mod, p_pattern => 'appointments/:reference');

    ORDS.DEFINE_PARAMETER(
        p_module_name => c_mod, p_pattern => 'appointments/:reference', p_method => 'GET',
        p_name => 'reference', p_bind_variable_name => 'reference',
        p_source_type => 'URI', p_param_type => 'STRING',
        p_access_method => 'IN', p_comments => 'booking reference');

    ORDS.DEFINE_HANDLER(
        p_module_name => c_mod,
        p_pattern     => 'appointments/:reference',
        p_method      => 'GET',
        p_source_type => 'json/item',
        p_source      => q'[
            SELECT a.booking_ref,
                   a.status,
                   TO_CHAR(s.slot_date,'YYYY-MM-DD') AS slot_date,
                   s.start_time,
                   s.end_time,
                   d.full_name  AS doctor_name,
                   d.room_no,
                   d.consult_fee,
                   dp.dept_name,
                   p.uhid,
                   p.full_name  AS patient_name,
                   p.phone,
                   TO_CHAR(a.booked_at,'YYYY-MM-DD HH24:MI') AS booked_at,
                   a.cancel_reason,
                   q.token_no,
                   NVL(q.queue_status,'NOT_CHECKED_IN') AS queue_status
              FROM girish_appointments a
              JOIN girish_slots s      ON s.slot_id    = a.slot_id
              JOIN girish_doctors d    ON d.doctor_id  = s.doctor_id
              JOIN girish_departments dp ON dp.dept_id = d.dept_id
              JOIN girish_patients p   ON p.patient_id = a.patient_id
              LEFT OUTER JOIN girish_token_queue q
                   ON q.appointment_id = a.appointment_id
             WHERE a.booking_ref = :reference
        ]');

    ---------------------------------------------------------------------------
    -- 11. PUT appointments/cancel   body: {"reference":"OPD-...","reason":"..."}
    --     Refund band comes from GIRISH_CANCELLATION_RULES (data, not code).
    ---------------------------------------------------------------------------
    ORDS.DEFINE_TEMPLATE(p_module_name => c_mod, p_pattern => 'appointments/cancel');

    ORDS.DEFINE_HANDLER(
        p_module_name => c_mod,
        p_pattern     => 'appointments/cancel',
        p_method      => 'PUT',
        p_source_type => 'plsql/block',
        p_source      => q'[
DECLARE
    l_ref      VARCHAR2(20) := JSON_VALUE(:body, '$.reference');
    l_reason   VARCHAR2(400) := JSON_VALUE(:body, '$.reason');
    l_appt_id  NUMBER;
    l_slot_id  NUMBER;
    l_status   girish_appointments.status%TYPE;
    l_fee      NUMBER;
    l_start    DATE;
    l_hours    NUMBER;
    l_pct      NUMBER := 0;
    l_penalty  NUMBER := 0;
    l_refund   NUMBER := 0;
    l_txn      VARCHAR2(40);
BEGIN
    IF l_ref IS NULL THEN
        :status := 400;
        :body   := '{"status":"BAD_REQUEST","message":"reference is required"}';
        RETURN;
    END IF;

    BEGIN
        SELECT a.appointment_id, a.slot_id, a.status, NVL(a.consult_fee,0),
               TO_DATE(TO_CHAR(s.slot_date,'YYYY-MM-DD') || ' ' || s.start_time,
                       'YYYY-MM-DD HH24:MI')
          INTO l_appt_id, l_slot_id, l_status, l_fee, l_start
          FROM girish_appointments a
          JOIN girish_slots s ON s.slot_id = a.slot_id
         WHERE a.booking_ref = l_ref
           FOR UPDATE OF a.status;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            :status := 404;
            :body   := '{"status":"NOT_FOUND","message":"Booking reference not found"}';
            RETURN;
    END;

    IF l_status IN ('CANCELLED','COMPLETED','NO_SHOW','EXPIRED') THEN
        ROLLBACK;
        :status := 409;
        :body   := JSON_OBJECT('status'  VALUE 'CONFLICT',
                               'message' VALUE 'This booking can no longer be cancelled',
                               'current_status' VALUE l_status RETURNING CLOB);
        RETURN;
    END IF;

    l_hours := (l_start - SYSDATE) * 24;

    IF l_hours <= 0 THEN
        ROLLBACK;
        :status := 400;
        :body   := '{"status":"BAD_REQUEST","message":"Cancellation window closed: slot has already started"}';
        RETURN;
    END IF;

    IF l_status = 'HELD' THEN
        l_pct := 0;               -- nothing was paid yet
    ELSE
        BEGIN
            SELECT refund_percent, penalty_amount
              INTO l_pct, l_penalty
              FROM girish_cancellation_rules
             WHERE is_active = 'Y'
               AND min_hours_before <= l_hours
               AND (max_hours_before IS NULL OR l_hours < max_hours_before)
             ORDER BY min_hours_before DESC
             FETCH FIRST 1 ROW ONLY;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                l_pct := 0;
                l_penalty := 0;
        END;
    END IF;

    l_refund := ROUND(l_fee * l_pct / 100, 2);

    UPDATE girish_appointments
       SET status          = 'CANCELLED',
           cancelled_at    = SYSTIMESTAMP,
           hold_expires_at = NULL,
           cancel_reason   = l_reason
     WHERE appointment_id = l_appt_id;

    IF l_refund > 0 THEN
        l_txn := 'RFD-' || TO_CHAR(SYSTIMESTAMP,'YYYYMMDDHH24MISS') || '-' || l_appt_id;
        INSERT INTO girish_payments (appointment_id, entry_type, payment_mode,
                                     txn_ref, amount, status)
        VALUES (l_appt_id, 'REFUND', 'SYSTEM', l_txn, l_refund, 'REFUNDED');
    END IF;

    -- release the seat
    UPDATE girish_slots
       SET current_bookings = GREATEST(current_bookings - 1, 0),
           status = CASE WHEN status = 'BOOKED' THEN 'AVAILABLE' ELSE status END
     WHERE slot_id = l_slot_id;

    COMMIT;
    :status := 200;
    :body   := JSON_OBJECT('status'         VALUE 'CANCELLED',
                           'reference'      VALUE l_ref,
                           'hours_before'   VALUE ROUND(l_hours,2),
                           'refund_percent' VALUE l_pct,
                           'refund_amount'  VALUE l_refund,
                           'penalty_amount' VALUE l_penalty RETURNING CLOB);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DECLARE
            PRAGMA AUTONOMOUS_TRANSACTION;
        BEGIN
            INSERT INTO girish_error_log (module_name, error_code, error_message)
            VALUES ('ORDS cancel appointment', TO_CHAR(SQLCODE), SUBSTR(SQLERRM,1,4000));
            COMMIT;
        END;
        :status := 500;
        :body   := JSON_OBJECT('status'  VALUE 'ERROR',
                               'message' VALUE SUBSTR(SQLERRM,1,400) RETURNING CLOB);
END;
        ]');

    ---------------------------------------------------------------------------
    -- 12. GET admin/appointments?status=&date=&doctor_id=
    ---------------------------------------------------------------------------
    ORDS.DEFINE_TEMPLATE(p_module_name => c_mod, p_pattern => 'admin/appointments/');

    ORDS.DEFINE_PARAMETER(
        p_module_name => c_mod, p_pattern => 'admin/appointments/', p_method => 'GET',
        p_name => 'status', p_bind_variable_name => 'status',
        p_source_type => 'QUERY', p_param_type => 'STRING',
        p_access_method => 'IN', p_comments => 'HELD, CONFIRMED, CHECKED_IN, ...');

    ORDS.DEFINE_PARAMETER(
        p_module_name => c_mod, p_pattern => 'admin/appointments/', p_method => 'GET',
        p_name => 'date', p_bind_variable_name => 'date',
        p_source_type => 'QUERY', p_param_type => 'STRING',
        p_access_method => 'IN', p_comments => 'slot date YYYY-MM-DD');

    ORDS.DEFINE_PARAMETER(
        p_module_name => c_mod, p_pattern => 'admin/appointments/', p_method => 'GET',
        p_name => 'doctor_id', p_bind_variable_name => 'doctor_id',
        p_source_type => 'QUERY', p_param_type => 'STRING',
        p_access_method => 'IN', p_comments => 'doctor id');

    ORDS.DEFINE_HANDLER(
        p_module_name    => c_mod,
        p_pattern        => 'admin/appointments/',
        p_method         => 'GET',
        p_source_type    => 'json/collection',
        p_items_per_page => 100,
        p_source         => q'[
            SELECT a.booking_ref,
                   a.status,
                   TO_CHAR(s.slot_date,'YYYY-MM-DD') AS slot_date,
                   s.start_time,
                   d.full_name AS doctor_name,
                   dp.dept_name,
                   p.full_name AS patient_name,
                   p.phone,
                   a.consult_fee,
                   NVL(q.token_no,'-') AS token_no,
                   NVL(q.queue_status,'-') AS queue_status
              FROM girish_appointments a
              JOIN girish_slots s        ON s.slot_id   = a.slot_id
              JOIN girish_doctors d      ON d.doctor_id = s.doctor_id
              JOIN girish_departments dp ON dp.dept_id  = d.dept_id
              JOIN girish_patients p     ON p.patient_id = a.patient_id
              LEFT OUTER JOIN girish_token_queue q
                   ON q.appointment_id = a.appointment_id
             WHERE (:status    IS NULL OR a.status = UPPER(:status))
               AND (:date      IS NULL OR s.slot_date = TO_DATE(:date,'YYYY-MM-DD'))
               AND (:doctor_id IS NULL OR d.doctor_id = TO_NUMBER(:doctor_id))
             ORDER BY s.slot_date DESC, s.start_time
        ]');

    ---------------------------------------------------------------------------
    -- 13. POST admin/departments/   body: {"dept_code","dept_name","floor_no"}
    --     Row-by-row insert with an immediate COMMIT: no big transaction, so
    --     this is the safe way to load data when a large script hits ORA-30036.
    ---------------------------------------------------------------------------
    ORDS.DEFINE_TEMPLATE(p_module_name => c_mod, p_pattern => 'admin/departments/');

    ORDS.DEFINE_HANDLER(
        p_module_name => c_mod,
        p_pattern     => 'admin/departments/',
        p_method      => 'POST',
        p_source_type => 'plsql/block',
        p_source      => q'[
DECLARE
    l_code  girish_departments.dept_code%TYPE := UPPER(JSON_VALUE(:body, '$.dept_code'));
    l_name  girish_departments.dept_name%TYPE := JSON_VALUE(:body, '$.dept_name');
    l_floor NUMBER := TO_NUMBER(JSON_VALUE(:body, '$.floor_no'));
    l_id    NUMBER;
BEGIN
    IF l_code IS NULL OR l_name IS NULL THEN
        :status := 400;
        :body   := '{"status":"BAD_REQUEST","message":"dept_code and dept_name are required"}';
        RETURN;
    END IF;

    INSERT INTO girish_departments (dept_code, dept_name, floor_no)
    VALUES (l_code, l_name, l_floor)
    RETURNING dept_id INTO l_id;

    COMMIT;
    :status := 201;
    :body   := JSON_OBJECT('status'    VALUE 'CREATED',
                           'dept_id'   VALUE l_id,
                           'dept_code' VALUE l_code,
                           'dept_name' VALUE l_name RETURNING CLOB);
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        ROLLBACK;
        :status := 409;
        :body   := '{"status":"CONFLICT","message":"Department code or name already exists"}';
    WHEN OTHERS THEN
        ROLLBACK;
        DECLARE
            PRAGMA AUTONOMOUS_TRANSACTION;
        BEGIN
            INSERT INTO girish_error_log (module_name, error_code, error_message)
            VALUES ('ORDS POST department', TO_CHAR(SQLCODE), SUBSTR(SQLERRM,1,4000));
            COMMIT;
        END;
        :status := 500;
        :body   := JSON_OBJECT('status' VALUE 'ERROR',
                               'message' VALUE SUBSTR(SQLERRM,1,400) RETURNING CLOB);
END;
        ]');

    ---------------------------------------------------------------------------
    -- 14. POST admin/doctors/   body: {"dept_code" or "dept_id","emp_code",
    --                                  "full_name","email","consult_fee", ...}
    ---------------------------------------------------------------------------
    ORDS.DEFINE_TEMPLATE(p_module_name => c_mod, p_pattern => 'admin/doctors/');

    ORDS.DEFINE_HANDLER(
        p_module_name => c_mod,
        p_pattern     => 'admin/doctors/',
        p_method      => 'POST',
        p_source_type => 'plsql/block',
        p_source      => q'[
DECLARE
    l_dept  NUMBER := TO_NUMBER(JSON_VALUE(:body, '$.dept_id'));
    l_code  girish_departments.dept_code%TYPE := UPPER(JSON_VALUE(:body, '$.dept_code'));
    l_emp   girish_doctors.emp_code%TYPE  := JSON_VALUE(:body, '$.emp_code');
    l_name  girish_doctors.full_name%TYPE := JSON_VALUE(:body, '$.full_name');
    l_email girish_doctors.email%TYPE     := LOWER(JSON_VALUE(:body, '$.email'));
    l_fee   NUMBER := TO_NUMBER(JSON_VALUE(:body, '$.consult_fee'));
    l_id    NUMBER;
BEGIN
    IF l_emp IS NULL OR l_name IS NULL OR l_email IS NULL OR l_fee IS NULL THEN
        :status := 400;
        :body   := '{"status":"BAD_REQUEST","message":"emp_code, full_name, email and consult_fee are required"}';
        RETURN;
    END IF;

    IF l_dept IS NULL THEN
        BEGIN
            SELECT dept_id INTO l_dept
              FROM girish_departments
             WHERE dept_code = l_code;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                :status := 400;
                :body   := '{"status":"BAD_REQUEST","message":"Unknown dept_code - create the department first"}';
                RETURN;
        END;
    END IF;

    INSERT INTO girish_doctors (dept_id, emp_code, full_name, qualification, email,
                                phone, room_no, consult_fee, languages)
    VALUES (l_dept, l_emp, l_name,
            JSON_VALUE(:body, '$.qualification'), l_email,
            JSON_VALUE(:body, '$.phone'), JSON_VALUE(:body, '$.room_no'), l_fee,
            JSON_VALUE(:body, '$.languages'))
    RETURNING doctor_id INTO l_id;

    COMMIT;
    :status := 201;
    :body   := JSON_OBJECT('status'  VALUE 'CREATED',
                           'doctor_id' VALUE l_id,
                           'emp_code'  VALUE l_emp,
                           'full_name' VALUE l_name,
                           'dept_id'   VALUE l_dept RETURNING CLOB);
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        ROLLBACK;
        :status := 409;
        :body   := '{"status":"CONFLICT","message":"Doctor emp_code or email already exists"}';
    WHEN OTHERS THEN
        ROLLBACK;
        DECLARE
            PRAGMA AUTONOMOUS_TRANSACTION;
        BEGIN
            INSERT INTO girish_error_log (module_name, error_code, error_message)
            VALUES ('ORDS POST doctor', TO_CHAR(SQLCODE), SUBSTR(SQLERRM,1,4000));
            COMMIT;
        END;
        :status := 500;
        :body   := JSON_OBJECT('status' VALUE 'ERROR',
                               'message' VALUE SUBSTR(SQLERRM,1,400) RETURNING CLOB);
END;
        ]');

    ---------------------------------------------------------------------------
    -- 15. POST admin/templates
    --     body: {"doctor_id":1,"all_weekdays":true,
    --            "start_time":"09:00","end_time":"11:00",
    --            "slot_minutes":15,"max_patients":2}
    --     all_weekdays=true -> Mon..Fri (1..5); otherwise send "day_of_week":1..7
    ---------------------------------------------------------------------------
    ORDS.DEFINE_TEMPLATE(p_module_name => c_mod, p_pattern => 'admin/templates/');

    ORDS.DEFINE_HANDLER(
        p_module_name => c_mod,
        p_pattern     => 'admin/templates/',
        p_method      => 'POST',
        p_source_type => 'plsql/block',
        p_source      => q'[
DECLARE
    l_doc     NUMBER := TO_NUMBER(JSON_VALUE(:body, '$.doctor_id'));
    l_day     NUMBER := TO_NUMBER(JSON_VALUE(:body, '$.day_of_week'));
    l_all     VARCHAR2(5) := LOWER(NVL(JSON_VALUE(:body, '$.all_weekdays'), 'false'));
    l_start   VARCHAR2(5) := NVL(JSON_VALUE(:body, '$.start_time'), '09:00');
    l_end     VARCHAR2(5) := NVL(JSON_VALUE(:body, '$.end_time'), '11:00');
    l_min     NUMBER := NVL(TO_NUMBER(JSON_VALUE(:body, '$.slot_minutes')), 15);
    l_max     NUMBER := NVL(TO_NUMBER(JSON_VALUE(:body, '$.max_patients')), 1);
    l_cnt     NUMBER := 0;
    l_exists  NUMBER;
BEGIN
    IF l_doc IS NULL THEN
        :status := 400;
        :body   := '{"status":"BAD_REQUEST","message":"doctor_id is required"}';
        RETURN;
    END IF;

    SELECT COUNT(*) INTO l_exists
      FROM girish_doctors WHERE doctor_id = l_doc AND is_active = 'Y';
    IF l_exists = 0 THEN
        :status := 400;
        :body   := '{"status":"BAD_REQUEST","message":"Unknown doctor_id"}';
        RETURN;
    END IF;

    IF l_all = 'true' THEN
        FOR i IN 1 .. 5 LOOP                 -- Mon..Fri
            INSERT INTO girish_slot_templates
                   (doctor_id, day_of_week, start_time, end_time,
                    slot_minutes, max_patients)
            VALUES (l_doc, i, l_start, l_end, l_min, l_max);
            l_cnt := l_cnt + 1;
        END LOOP;
    ELSE
        IF l_day IS NULL OR l_day NOT BETWEEN 1 AND 7 THEN
            ROLLBACK;
            :status := 400;
            :body   := '{"status":"BAD_REQUEST","message":"day_of_week 1-7 required unless all_weekdays=true"}';
            RETURN;
        END IF;
        INSERT INTO girish_slot_templates
               (doctor_id, day_of_week, start_time, end_time,
                slot_minutes, max_patients)
        VALUES (l_doc, l_day, l_start, l_end, l_min, l_max);
        l_cnt := 1;
    END IF;

    COMMIT;
    :status := 201;
    :body   := JSON_OBJECT('status'            VALUE 'CREATED',
                           'doctor_id'         VALUE l_doc,
                           'templates_created' VALUE l_cnt,
                           'start_time'        VALUE l_start,
                           'end_time'          VALUE l_end RETURNING CLOB);
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        ROLLBACK;
        :status := 409;
        :body   := '{"status":"CONFLICT","message":"A template already exists for that doctor, day and start time"}';
    WHEN OTHERS THEN
        ROLLBACK;
        DECLARE
            PRAGMA AUTONOMOUS_TRANSACTION;
        BEGIN
            INSERT INTO girish_error_log (module_name, error_code, error_message)
            VALUES ('ORDS POST template', TO_CHAR(SQLCODE), SUBSTR(SQLERRM,1,4000));
            COMMIT;
        END;
        :status := 500;
        :body   := JSON_OBJECT('status' VALUE 'ERROR',
                               'message' VALUE SUBSTR(SQLERRM,1,400) RETURNING CLOB);
END;
        ]');

    ---------------------------------------------------------------------------
    -- 16. GET templates/?doctor_id=   (check the weekly plan)
    ---------------------------------------------------------------------------
    ORDS.DEFINE_TEMPLATE(p_module_name => c_mod, p_pattern => 'templates/');

    ORDS.DEFINE_PARAMETER(
        p_module_name => c_mod, p_pattern => 'templates/', p_method => 'GET',
        p_name => 'doctor_id', p_bind_variable_name => 'doctor_id',
        p_source_type => 'QUERY', p_param_type => 'STRING',
        p_access_method => 'IN', p_comments => 'doctor id');

    ORDS.DEFINE_HANDLER(
        p_module_name    => c_mod,
        p_pattern        => 'templates/',
        p_method         => 'GET',
        p_source_type    => 'json/collection',
        p_items_per_page => 100,
        p_source         => q'[
            SELECT t.template_id,
                   t.doctor_id,
                   d.full_name AS doctor_name,
                   t.day_of_week,
                   CASE t.day_of_week WHEN 1 THEN 'Mon' WHEN 2 THEN 'Tue'
                        WHEN 3 THEN 'Wed' WHEN 4 THEN 'Thu' WHEN 5 THEN 'Fri'
                        WHEN 6 THEN 'Sat' ELSE 'Sun' END AS day_name,
                   t.start_time,
                   t.end_time,
                   t.slot_minutes,
                   t.max_patients
              FROM girish_slot_templates t
              JOIN girish_doctors d ON d.doctor_id = t.doctor_id
             WHERE t.is_active = 'Y'
               AND (:doctor_id IS NULL OR t.doctor_id = TO_NUMBER(:doctor_id))
             ORDER BY t.doctor_id, t.day_of_week, t.start_time
        ]');

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('ORDS module girish.opd.api published.');
END;
/

-- =============================================================================
--  END OF ORDS MODULE SCRIPT
--  Expect: 1 statement processed, 1 successful, 0 errors.
--  If you get ORA-01031 / ORA-06550 on ORDS.* : the schema is not ORDS-enabled.
--  Fix (once, as ADMIN) :  EXEC ORDS_ADMIN.ENABLE_SCHEMA(p_schema => 'NOV_2026_BATCH');
--  or simply use SQL Workshop -> RESTful Services -> create the module in the UI.
-- =============================================================================
