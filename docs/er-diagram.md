# ER Diagram — Hospital OPD Appointment Booking Platform

10 tables, all `GIRISH_` prefixed, in 3NF, with WHO audit columns on every row
(`CREATED_BY`, `CREATED_DATE`, `LAST_UPDATED_BY`, `LAST_UPDATED_DATE`) and soft delete via `IS_ACTIVE`.

---

## 1. Entity–relationship diagram

```mermaid
erDiagram
    GIRISH_DEPARTMENTS ||--o{ GIRISH_DOCTORS : "employs"
    GIRISH_DOCTORS ||--o{ GIRISH_SLOT_TEMPLATES : "defines weekly hours"
    GIRISH_SLOT_TEMPLATES |o--o{ GIRISH_SLOTS : "materialised into"
    GIRISH_DOCTORS ||--o{ GIRISH_SLOTS : "owns"
    GIRISH_PATIENTS ||--o{ GIRISH_APPOINTMENTS : "books"
    GIRISH_SLOTS ||--o{ GIRISH_APPOINTMENTS : "seats"
    GIRISH_APPOINTMENTS ||--o| GIRISH_TOKEN_QUEUE : "check-in issues"
    GIRISH_APPOINTMENTS ||--o{ GIRISH_PAYMENTS : "settled by"
    GIRISH_CANCELLATION_RULES |o..o{ GIRISH_APPOINTMENTS : "refund policy on cancel"

    GIRISH_DEPARTMENTS {
        NUMBER dept_id PK "IDENTITY ALWAYS"
        VARCHAR2 dept_code UK "CARD, NEURO, PEDIA"
        VARCHAR2 dept_name "Cardiology"
        NUMBER floor_no "physical location"
        CHAR is_active "Y / N soft delete"
        VARCHAR2 created_by "WHO audit"
        TIMESTAMP created_date "WHO audit"
        VARCHAR2 last_updated_by "WHO audit"
        TIMESTAMP last_updated_date "WHO audit"
    }

    GIRISH_DOCTORS {
        NUMBER doctor_id PK "IDENTITY ALWAYS"
        NUMBER dept_id FK "to GIRISH_DEPARTMENTS"
        VARCHAR2 emp_code UK "hospital employee id"
        VARCHAR2 full_name "Dr. Ananya Sharma"
        VARCHAR2 qualification "MD DM"
        VARCHAR2 email UK "login + notifications"
        VARCHAR2 phone
        VARCHAR2 room_no "OPD room"
        NUMBER consult_fee "OPD fee tier"
        VARCHAR2 languages "English, Hindi, Kannada"
        CHAR is_active "Y / N"
    }

    GIRISH_SLOT_TEMPLATES {
        NUMBER template_id PK "IDENTITY ALWAYS"
        NUMBER doctor_id FK "to GIRISH_DOCTORS"
        NUMBER day_of_week "1=Mon .. 7=Sun"
        VARCHAR2 start_time "HH24:MI e.g. 09:00"
        VARCHAR2 end_time "HH24:MI e.g. 13:00"
        NUMBER slot_minutes "15 / 20 / 30"
        NUMBER max_patients "capacity per slot"
        DATE effective_from "validity window"
        DATE effective_to "nullable = open ended"
        CHAR is_active "Y / N"
    }

    GIRISH_SLOTS {
        NUMBER slot_id PK "IDENTITY ALWAYS"
        NUMBER doctor_id FK "to GIRISH_DOCTORS"
        NUMBER template_id FK "nullable, provenance"
        DATE slot_date "20 Nov 2026"
        VARCHAR2 start_time "09:00"
        VARCHAR2 end_time "09:15"
        NUMBER max_capacity "copied from template"
        NUMBER current_bookings "active holds + confirmed"
        VARCHAR2 status "AVAILABLE / BOOKED / BLOCKED"
    }

    GIRISH_PATIENTS {
        NUMBER patient_id PK "IDENTITY ALWAYS"
        VARCHAR2 uhid UK "unique health id, MRN"
        VARCHAR2 full_name
        DATE dob
        CHAR gender "M / F / O"
        VARCHAR2 phone UK "booking lookup key"
        VARCHAR2 email
        VARCHAR2 blood_group "A+, O-, ..."
        CHAR is_active "Y / N"
    }

    GIRISH_APPOINTMENTS {
        NUMBER appointment_id PK "IDENTITY ALWAYS"
        VARCHAR2 booking_ref UK "OPD-202611-00042"
        NUMBER slot_id FK "to GIRISH_SLOTS"
        NUMBER patient_id FK "to GIRISH_PATIENTS"
        VARCHAR2 status "HELD..COMPLETED"
        NUMBER consult_fee "fee snapshot at booking"
        TIMESTAMP booked_at "when HELD was created"
        TIMESTAMP hold_expires_at "5 min TTL, null once confirmed"
        TIMESTAMP confirmed_at
        TIMESTAMP checked_in_at
        TIMESTAMP completed_at
        TIMESTAMP cancelled_at
        VARCHAR2 cancel_reason
    }

    GIRISH_TOKEN_QUEUE {
        NUMBER token_id PK "IDENTITY ALWAYS"
        NUMBER appointment_id FK "one token per visit"
        NUMBER doctor_id FK "queue is per doctor/day"
        DATE token_date "today"
        VARCHAR2 token_no "CARD-04"
        VARCHAR2 queue_status "WAITING / CALLED / DONE"
        TIMESTAMP called_at
    }

    GIRISH_PAYMENTS {
        NUMBER payment_id PK "IDENTITY ALWAYS"
        NUMBER appointment_id FK "to GIRISH_APPOINTMENTS"
        VARCHAR2 entry_type "CHARGE / REFUND"
        VARCHAR2 payment_mode "UPI / CARD / CASH"
        VARCHAR2 txn_ref "simulated gateway ref"
        NUMBER amount "positive = money in"
        VARCHAR2 status "SUCCESS / REFUNDED / FAILED"
        TIMESTAMP paid_at
    }

    GIRISH_CANCELLATION_RULES {
        NUMBER rule_id PK "IDENTITY ALWAYS"
        VARCHAR2 rule_name "more than 4h prior"
        NUMBER min_hours_before "lower bound, inclusive"
        NUMBER max_hours_before "upper bound, nullable"
        NUMBER refund_percent "100 / 50 / 0"
        NUMBER penalty_amount "flat fee retained"
        CHAR is_active "Y / N"
    }

    GIRISH_ERROR_LOG {
        NUMBER error_id PK "IDENTITY ALWAYS"
        VARCHAR2 module_name "GIRISH_OPD_PKG.HOLD_SLOT"
        VARCHAR2 error_code "ORA / custom -20001"
        VARCHAR2 error_message
        CLOB backtrace "DBMS_UTILITY.FORMAT_ERROR_BACKTRACE"
        VARCHAR2 logged_by "APEX user or USER"
        TIMESTAMP logged_at "SYSTIMESTAMP"
    }
```

---

## 2. Relationship summary

| # | Parent | Child | Cardinality | FK / rule |
|---|---|---|---|---|
| 1 | `DEPARTMENTS` | `DOCTORS` | 1 : N | `DOCTORS.DEPT_ID` — `ON DELETE RESTRICT` |
| 2 | `DOCTORS` | `SLOT_TEMPLATES` | 1 : N | `TEMPLATES.DOCTOR_ID` — `ON DELETE CASCADE` |
| 3 | `SLOT_TEMPLATES` | `SLOTS` | 1 : N (optional) | `SLOTS.TEMPLATE_ID` nullable — generated rows survive template edits |
| 4 | `DOCTORS` | `SLOTS` | 1 : N | `SLOTS.DOCTOR_ID` — `ON DELETE CASCADE` |
| 5 | `PATIENTS` | `APPOINTMENTS` | 1 : N | `APPOINTMENTS.PATIENT_ID` — `ON DELETE RESTRICT` |
| 6 | `SLOTS` | `APPOINTMENTS` | 1 : N | `APPOINTMENTS.SLOT_ID`; `N = SLOTS.MAX_CAPACITY` |
| 7 | `APPOINTMENTS` | `TOKEN_QUEUE` | 1 : 0..1 | `TOKEN_QUEUE.APPOINTMENT_ID` **UNIQUE** |
| 8 | `APPOINTMENTS` | `PAYMENTS` | 1 : N | append-only ledger: one `CHARGE` + optional `REFUND` |
| 9 | `CANCELLATION_RULES` | `APPOINTMENTS` | logical (no FK) | resolved by hours-before-slot at cancel time |

The dashed line for rule 9 is deliberate: cancellation policy is **configuration**, matched by a
range predicate, not a physical foreign key. That is what lets the hospital change refund bands
without touching code.

---

## 3. Why `APPOINTMENTS` has no `DOCTOR_ID`

The doctor is reachable through `SLOT_ID → SLOTS.DOCTOR_ID`. Storing it again would create a
transitive dependency (`SLOT_ID → DOCTOR_ID`), which is a 3NF violation, and would allow rows where
the appointment's doctor disagrees with the slot's doctor. Reports join
`APPOINTMENTS → SLOTS → DOCTORS` (an inner join — a concept the rubric asks to demonstrate).

`CONSULT_FEE` **is** duplicated on the appointment, intentionally: it is a historical snapshot of
what the patient was charged, and must not change when the doctor's current fee changes.

---

## 4. Key constraints and indexes

| Object | Definition | Purpose |
|---|---|---|
| `UK_SLOTS_DOC_TIME` | `UNIQUE (DOCTOR_ID, SLOT_DATE, START_TIME)` | one physical slot per doctor per time; makes `GENERATE_SLOTS` re-runnable |
| `UK_APPT_REF` | `UNIQUE (BOOKING_REF)` | reference is the public handle used by every endpoint |
| `UK_PATIENT_PHONE` / `UK_PATIENT_UHID` | unique | prevents duplicate patient records from reception |
| `UK_TOKEN_DOC_DATE_NO` | `UNIQUE (DOCTOR_ID, TOKEN_DATE, TOKEN_NO)` | token numbers never repeat within a doctor's day |
| `UK_TOKEN_APPT` | `UNIQUE (APPOINTMENT_ID)` on `TOKEN_QUEUE` | check-in is idempotent |
| `CK_SLOT_STATUS` | `STATUS IN ('AVAILABLE','BOOKED','BLOCKED')` | slot state machine |
| `CK_APPT_STATUS` | `STATUS IN ('HELD','CONFIRMED','CHECKED_IN','COMPLETED','CANCELLED','NO_SHOW','EXPIRED')` | appointment state machine |
| `CK_SLOT_CAPACITY` | `CURRENT_BOOKINGS BETWEEN 0 AND MAX_CAPACITY` | last line of defence against overbooking |
| `CK_PATIENT_GENDER` | `GENDER IN ('M','F','O')` | matches data-standard rule |
| `CK_RULE_RANGE` | `REFUND_PERCENT BETWEEN 0 AND 100` | sane refund configuration |
| `IX_APPT_PATIENT` | `(PATIENT_ID, BOOKED_AT DESC)` | "My Bookings" page |
| `IX_APPT_STATUS_DATE` | `(STATUS, BOOKED_AT)` | no-show sweep + admin filters |
| `IX_SLOT_DOC_DATE` | `(DOCTOR_ID, SLOT_DATE, STATUS)` | availability lookup (the hottest query) |
| `IX_TOKEN_DOC_DATE` | `(DOCTOR_ID, TOKEN_DATE, QUEUE_STATUS)` | doctor's live queue |
| `IX_PAY_APPT` | `(APPOINTMENT_ID)` | slip / receipt lookup |

Sequences: `SEQ_BOOKING_REF` (reference numbers), `SEQ_TOKEN_NO` (daily token), plus identity
columns for surrogate keys. Business references are generated with a sequence, never `MAX()+1`.

---

## 5. Concurrency contract (how the diagram stays true under load)

```
HOLD_SLOT:
  SELECT MAX_CAPACITY, CURRENT_BOOKINGS, STATUS
    FROM GIRISH_SLOTS WHERE SLOT_ID = p_slot_id
     FOR UPDATE;                       -- pessimistic row lock, one waiter at a time
  IF STATUS <> 'AVAILABLE' OR CURRENT_BOOKINGS >= MAX_CAPACITY THEN
     RAISE e_slot_full;                -- → 409 Conflict
  END IF;
  UPDATE GIRISH_SLOTS SET CURRENT_BOOKINGS = CURRENT_BOOKINGS + 1 ...
  INSERT INTO GIRISH_APPOINTMENTS (..., STATUS, HOLD_EXPIRES_AT)
       VALUES (..., 'HELD', SYSTIMESTAMP + INTERVAL '5' MINUTE);
  COMMIT;
```

`CK_SLOT_CAPACITY` guarantees that even a future code path that forgets the lock cannot write a
slot over capacity. Optimistic control is used where a lost update is harmless (e.g. admin edits,
via `LAST_UPDATED_DATE` comparison before `UPDATE`).

---

## 6. Audit, soft delete and error handling

- **WHO columns** — defaults `SYSDATE` and
  `COALESCE(SYS_CONTEXT('APEX$SESSION','APP_USER'), USER)`, refreshed by a `BEFORE UPDATE` trigger so
  `LAST_UPDATED_BY/DATE` can never be spoofed by application code.
- **Soft delete** — `IS_ACTIVE = 'N'` on master tables; slots and appointments are never deleted, only
  status-transitioned, so utilisation history stays intact.
- **Error log** — every public package procedure wraps its body in `EXCEPTION WHEN OTHERS` and calls
  `LOG_ERROR` (autonomous transaction), so a failed booking still leaves a trace after the caller's
  `ROLLBACK`.
