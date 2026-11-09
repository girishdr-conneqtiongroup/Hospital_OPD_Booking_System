-- =============================================================================
--  GIRISH OPD  |  FILE 00 : DROP ALL GIRISH_* OBJECTS  (clean rebuild helper)
--  Workspace / schema : NOV_2026_BATCH        DB : Oracle 23ai (APEX 26.1)
-- -----------------------------------------------------------------------------
--  Deletes EVERY object in this schema whose name starts with GIRISH_
--  (tables + their indexes/constraints, standalone triggers, views, sequences).
--  Nothing else in the workspace is touched - other batch members' tables
--  (EMPLOYEE_MASTER, CART_*, ...) are not matched by the GIRISH_ filter.
--
--  HOW TO RUN
--    SQL Workshop -> SQL Scripts -> Create -> paste -> Run
--    (The closing "/" line tells SQL Scripts the PL/SQL block has ended.
--     Pasting into SQL Commands instead? Delete that last "/" line.)
--
--  Safe to run twice: already-missing objects are skipped, not errors.
-- =============================================================================
DECLARE
    PROCEDURE run_sql(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            NULL;   -- object already gone / not droppable here: keep going
    END;
BEGIN
    -- 1. views first (they depend on the tables)
    FOR r IN (SELECT view_name FROM user_views
               WHERE view_name LIKE 'GIRISH\_%' ESCAPE '\') LOOP
        run_sql('DROP VIEW ' || r.view_name);
        DBMS_OUTPUT.PUT_LINE('dropped view      : ' || r.view_name);
    END LOOP;

    -- 2. standalone triggers (table triggers vanish with their table anyway)
    FOR r IN (SELECT trigger_name FROM user_triggers
               WHERE trigger_name LIKE 'GIRISH\_%' ESCAPE '\') LOOP
        run_sql('DROP TRIGGER ' || r.trigger_name);
        DBMS_OUTPUT.PUT_LINE('dropped trigger   : ' || r.trigger_name);
    END LOOP;

    -- 3. tables (CASCADE CONSTRAINTS removes FKs + indexes, PURGE skips recycle bin)
    FOR r IN (SELECT table_name FROM user_tables
               WHERE table_name LIKE 'GIRISH\_%' ESCAPE '\') LOOP
        run_sql('DROP TABLE ' || r.table_name || ' CASCADE CONSTRAINTS PURGE');
        DBMS_OUTPUT.PUT_LINE('dropped table     : ' || r.table_name);
    END LOOP;

    -- 4. sequences
    FOR r IN (SELECT sequence_name FROM user_sequences
               WHERE sequence_name LIKE 'GIRISH\_%' ESCAPE '\'
                  OR sequence_name LIKE 'SEQ\_GIRISH\_%' ESCAPE '\') LOOP
        run_sql('DROP SEQUENCE ' || r.sequence_name);
        DBMS_OUTPUT.PUT_LINE('dropped sequence  : ' || r.sequence_name);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('--- GIRISH_* cleanup complete ---');
END;
/

-- Verify nothing is left (should return 0 rows):
--   SELECT table_name FROM user_tables WHERE table_name LIKE 'GIRISH\_%' ESCAPE '\';
