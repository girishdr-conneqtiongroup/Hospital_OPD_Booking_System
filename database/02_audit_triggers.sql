-- =============================================================================
--  GIRISH OPD  |  Hospital Appointment Booking Platform
--  FILE 02 : AUDIT TRIGGERS  (Phase 1, Step 1.4)
--  Workspace / schema : NOV_2026_BATCH        DB : Oracle 23ai (APEX 26.1)
-- -----------------------------------------------------------------------------
--  WHAT THESE DO
--    The column DEFAULTs already stamp CREATED_BY / CREATED_DATE on INSERT.
--    These BEFORE UPDATE triggers refresh LAST_UPDATED_BY / LAST_UPDATED_DATE
--    so no application code (APEX, ORDS, Postman, SQL Workshop) can forget
--    them or fake them.
--
--  HOW TO RUN  ->  SQL Workshop -> SQL Scripts -> Create -> paste -> Run
--    Every block is followed by a line containing only "/" because that is
--    what APEX SQL Scripts uses to close a PL/SQL block. Without it you get
--    "PLS-00103: Encountered the symbol CREATE".
--
--    Running this in SQL Commands instead? Paste ONE block at a time and
--    delete that block's "/" line (SQL Commands terminates by itself).
--
--  Run FILE 01 first - triggers need the tables to exist.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. DEPARTMENTS
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_GIRISH_DEPT_BU
BEFORE UPDATE ON GIRISH_DEPARTMENTS
FOR EACH ROW
BEGIN
    :NEW.LAST_UPDATED_BY   := COALESCE(SYS_CONTEXT('APEX$SESSION','APP_USER'), USER);
    :NEW.LAST_UPDATED_DATE := SYSTIMESTAMP;
END;
/

-- -----------------------------------------------------------------------------
-- 2. DOCTORS
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_GIRISH_DOC_BU
BEFORE UPDATE ON GIRISH_DOCTORS
FOR EACH ROW
BEGIN
    :NEW.LAST_UPDATED_BY   := COALESCE(SYS_CONTEXT('APEX$SESSION','APP_USER'), USER);
    :NEW.LAST_UPDATED_DATE := SYSTIMESTAMP;
END;
/

-- -----------------------------------------------------------------------------
-- 3. SLOT TEMPLATES
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_GIRISH_TPL_BU
BEFORE UPDATE ON GIRISH_SLOT_TEMPLATES
FOR EACH ROW
BEGIN
    :NEW.LAST_UPDATED_BY   := COALESCE(SYS_CONTEXT('APEX$SESSION','APP_USER'), USER);
    :NEW.LAST_UPDATED_DATE := SYSTIMESTAMP;
END;
/

-- -----------------------------------------------------------------------------
-- 4. SLOTS
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_GIRISH_SLOT_BU
BEFORE UPDATE ON GIRISH_SLOTS
FOR EACH ROW
BEGIN
    :NEW.LAST_UPDATED_BY   := COALESCE(SYS_CONTEXT('APEX$SESSION','APP_USER'), USER);
    :NEW.LAST_UPDATED_DATE := SYSTIMESTAMP;
END;
/

-- -----------------------------------------------------------------------------
-- 5. PATIENTS
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_GIRISH_PAT_BU
BEFORE UPDATE ON GIRISH_PATIENTS
FOR EACH ROW
BEGIN
    :NEW.LAST_UPDATED_BY   := COALESCE(SYS_CONTEXT('APEX$SESSION','APP_USER'), USER);
    :NEW.LAST_UPDATED_DATE := SYSTIMESTAMP;
END;
/

-- -----------------------------------------------------------------------------
-- 6. APPOINTMENTS
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_GIRISH_APPT_BU
BEFORE UPDATE ON GIRISH_APPOINTMENTS
FOR EACH ROW
BEGIN
    :NEW.LAST_UPDATED_BY   := COALESCE(SYS_CONTEXT('APEX$SESSION','APP_USER'), USER);
    :NEW.LAST_UPDATED_DATE := SYSTIMESTAMP;
END;
/

-- -----------------------------------------------------------------------------
-- 7. TOKEN QUEUE
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_GIRISH_TOKEN_BU
BEFORE UPDATE ON GIRISH_TOKEN_QUEUE
FOR EACH ROW
BEGIN
    :NEW.LAST_UPDATED_BY   := COALESCE(SYS_CONTEXT('APEX$SESSION','APP_USER'), USER);
    :NEW.LAST_UPDATED_DATE := SYSTIMESTAMP;
END;
/

-- -----------------------------------------------------------------------------
-- 8. PAYMENTS
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_GIRISH_PAY_BU
BEFORE UPDATE ON GIRISH_PAYMENTS
FOR EACH ROW
BEGIN
    :NEW.LAST_UPDATED_BY   := COALESCE(SYS_CONTEXT('APEX$SESSION','APP_USER'), USER);
    :NEW.LAST_UPDATED_DATE := SYSTIMESTAMP;
END;
/

-- -----------------------------------------------------------------------------
-- 9. CANCELLATION RULES
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_GIRISH_RULE_BU
BEFORE UPDATE ON GIRISH_CANCELLATION_RULES
FOR EACH ROW
BEGIN
    :NEW.LAST_UPDATED_BY   := COALESCE(SYS_CONTEXT('APEX$SESSION','APP_USER'), USER);
    :NEW.LAST_UPDATED_DATE := SYSTIMESTAMP;
END;
/

-- =============================================================================
--  END OF FILE 02  -> expect "9 Statements Processed, 9 Successful, 0 Errors"
--  Next : FILE 99 (verification)
-- =============================================================================
