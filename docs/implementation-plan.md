# Phase-by-Phase Implementation Plan — Hospital OPD Booking Platform

**Stack:** Oracle Autonomous Database (23ai) · PL/SQL package `GIRISH_OPD_PKG` · ORDS · Oracle APEX 26
**Checkpoints:** Day 11 (DB + PL/SQL) · Day 12 (API) · Day 13 (UI) · Day 14 (reports + concurrency) · Day 15 (demo)
**Rule for every phase:** no phase starts until the previous phase's *exit criteria* are met. Each phase ends with a Git commit, an export saved into the repo, and one recorded proof (screenshot, Postman run, or SQL output).

---

## Phase 0 — Environment & repository (Day 1–2, ~2 h)

**Goal:** a place to store work and a verified connection to the cloud database.

| Step | Action | Done when |
|---|---|---|
| 0.1 | Create schema/user in ADB, confirm SQL Workshop access | `select user, sysdate from dual;` runs in browser |
| 0.2 | Create GitHub repo + folder skeleton `database/ api/ apex/ docs/` | `git push` succeeds |
| 0.3 | Install Postman, create workspace + environment (`base_url`, `schema`) | Postman can hit `https://<host>/ords/` |
| 0.4 | Confirm ORDS is enabled on the schema (`ORDS.ENABLE_SCHEMA`) | Schema appears in ORDS-enabled list |
| 0.5 | Commit `docs/` (architecture, process-flow, ER diagrams) | Docs visible on GitHub |

**Exit criteria:** empty repo pushed, ADB reachable from both APEX and Postman.
**Risk:** ORDS not enabled / wallet issues → resolve now, not on Day 12.

---

## Phase 1 — Database architecture & DDL (Day 11, first half · ~4 h)

**Goal:** all 10 tables exist, normalized, constrained, seeded, with audit defaults.

| Step | Action | Output |
|---|---|---|
| 1.1 | Write DDL for the 10 `GIRISH_` tables in dependency order (departments → doctors → templates → slots → patients → appointments → token_queue → payments → cancellation_rules → error_log) | `database/01_ddl_tables.sql` |
| 1.2 | Constraints: PK (identity), FKs with `ON DELETE` actions, unique keys (`DOCTOR.EMAIL`, `PATIENT.PHONE/UHID`, `APPOINTMENT.BOOKING_REF`, slot doctor+date+time, token per doctor/day), checks (`STATUS` lists, `GENDER`, `CURRENT_BOOKINGS <= MAX_CAPACITY`, `REFUND_PERCENT 0–100`) | same file |
| 1.3 | Indexes for the hot paths: availability lookup, my-bookings, no-show sweep, token queue | `database/03_indexes.sql` |
| 1.4 | Sequences: booking reference + daily token + reporting helpers | `database/02_sequences.sql` |
| 1.5 | WHO audit defaults (`SYSDATE`, `COALESCE(SYS_CONTEXT('APEX$SESSION','APPR_USER'), USER)`) + `BEFORE UPDATE` audit trigger | `database/04_triggers.sql` |
| 1.6 | Seed ≥ 50 rows: 6 departments, 12 doctors, 15 templates, 25 patients, 5 cancellation rules | `database/05_seed_data.sql` |
| 1.7 | Verify | `select count(*)` per table; deliberately insert a bad status and a bad gender → both rejected |

**Exit criteria:** every table ≥ 50 rows total across seed; constraint violations demonstrably blocked; ER diagram matches actual columns (no drift).
**Do not** generate slots yet — that is Phase 2.
**Risk:** check-constraint naming drift → fix names now, they are quoted in the API error mapping later.

---

## Phase 2 — Core PL/SQL package (Day 11, second half · ~5 h)

**Goal:** every business rule lives in one package; nothing is validated in APEX or ORDS.

Build in this order — each procedure is testable immediately from SQL Workshop:

| # | Unit | Must do | Test to run |
|---|---|---|---|
| 2.1 | `LOG_ERROR` | autonomous transaction insert into `GIRISH_ERROR_LOG` | force an error, confirm row persists after rollback |
| 2.2 | `GENERATE_SLOTS(doctor, from, to)` | read templates, match `DAY_OF_WEEK`, split hours into `SLOT_MINUTES` intervals, skip duplicates | generate one month for 2 doctors; re-run → no duplicates |
| 2.3 | `HOLD_SLOT(slot, patient, out ref, out status, out msg)` | `SELECT ... FOR UPDATE`, capacity + status check, insert `HELD` with 5-min expiry, increment counter | book until full → next call returns sold-out status |
| 2.4 | `CONFIRM_APPOINTMENT(ref, mode, ...)` | reject expired/invalid hold, set `CONFIRMED`, write `CHARGE` payment row | confirm a held ref; timeout case → rejected |
| 2.5 | `CHECKIN_AND_GENERATE_TOKEN(ref, ...)` | only `CONFIRMED` today, compute next token per doctor/day, insert token | two check-ins → tokens 01, 02 |
| 2.6 | `CANCEL_APPOINTMENT(ref, reason, ...)` | resolve refund band from rules table, insert `REFUND` row if > 0, decrement capacity, reject after slot start | cancel 6 h before (100 %), 1 h before (50 %), after start (error) |
| 2.7 | `RELEASE_NO_SHOWS()` | batch: `CONFIRMED` past start + grace → `NO_SHOW`, decrement | backdate a slot → sweep frees the seat |
| 2.8 | Report functions (utilisation %, no-show %) | `RETURN` values used by Phase 5 | compare with manual SQL |
| 2.9 | Package spec + body assembly, private helpers, error constants | compile with zero warnings | `show errors` |

**Technique checkpoints (rubric):** explicit + parameterized cursors, cursor FOR loop, `%ROWTYPE`, associative array, nested table, `BULK COLLECT` + `FORALL` (in the sweep and seed utilities), user-defined exceptions, `EXECUTE IMMEDIATE` (dynamic table name in an admin utility), savepoint/rollback demo procedure, package-level variables.

**Exit criteria:** all 8 procedures callable from SQL Workshop with expected outputs; errors land in `GIRISH_ERROR_LOG`; package compiles clean.
**Risk:** capacity accounting inconsistency (hold vs confirm) → decide once: counter increments on **hold**, decrements on expiry/cancel/no-show (see `docs/process-flow.md` §4).

---

## Phase 3 — ORDS REST API (Day 12 · ~5 h)

**Goal:** 6+ endpoints returning clean JSON, driven only by the package.

| Step | Endpoint | Maps to |
|---|---|---|
| 3.1 | `GET /v1/departments` | departments + doctor count (group by / having) |
| 3.2 | `GET /v1/doctors?dept_id=&q=` | filter by department or name |
| 3.3 | `GET /v1/availability?doc_id=&date=` | free slots + remaining capacity; 404 when none |
| 3.4 | `POST /v1/appointments/book` | `HOLD_SLOT` → 201 / 409 sold out / 400 bad input |
| 3.5 | `POST /v1/appointments/confirm` | `CONFIRM_APPOINTMENT` → 200 / 409 expired hold |
| 3.6 | `GET /v1/appointments/:reference` | status + doctor + room + token; 404 unknown ref |
| 3.7 | `PUT /v1/appointments/cancel` | 200 with refund amount / 400 window closed / 404 |
| 3.8 | `GET /v1/admin/appointments?status=&date=&doctor_id=` | filterable admin list |
| 3.9 | Postman collection | 10+ assertions incl. double-booking 409, invalid reference, cancel-after-start, capacity reflection |

Error contract: map package errors to HTTP (`-20001 slot full` → 409, `-20002 hold expired` → 409, `-20003 window closed` → 400, `no_data_found` → 404). Never leak `ORA-` text — but log it.

**Exit criteria:** full Postman run green (Collection Runner, ordered); exported collection committed to `api/`.
**Risk:** ORDS handler escaping / date formats → fix `TO_DATE(...,'YYYY-MM-DD')` conventions in one place.

---

## Phase 4 — APEX application (Day 13 · ~7 h)

**Goal:** 8 pages, custom-themed (medical blue #1976D2), role-aware, mobile-usable.

| Step | Page | Key objects |
|---|---|---|
| 4.1 | App shell: Universal Theme, custom CSS variables, navigation by role, logo/branding | auth scheme + 4 authorization schemes |
| 4.2 | P1 Landing + doctor search | Cards region, faceted search (department, fee band), badges |
| 4.3 | P2 Slot selection + booking | Calendar + slot cards, modal patient form, live hold countdown (dynamic action + JS timer) |
| 4.4 | P3 Confirmation slip | success badge, reference, room, print CSS |
| 4.5 | P4 My bookings | search by phone/UHID, status chips, cancel + download slip |
| 4.6 | P5 Reception / check-in | ref lookup → token displayed large, queue list |
| 4.7 | P6 Doctor desk | today's queue in token order, Call / Complete / No-Show buttons |
| 4.8 | P7 Admin master data | interactive grids: departments, doctors, templates + "Generate slots" button |
| 4.9 | P8 Dashboards | KPI tiles (progress indicators), utilisation bar, no-show donut + trend |
| 4.10 | Export app | `apex/fXXXXX.sql` committed |

**Exit criteria:** happy path bookable end-to-end in the UI; each role hides the pages it must not see; no page uses inline validation that duplicates the package.
**Risk:** time sink in CSS → cap styling at theme variables + a small CSS block; the layout is already good.

---

## Phase 5 — Reports & analytics (Day 14, first half · ~3 h)

| Step | Report | SQL concepts exercised |
|---|---|---|
| 5.1 | Doctor utilisation: completed ÷ available slots per doctor per range, bar + gauge + table | joins `APPOINTMENTS → SLOTS → DOCTORS → DEPARTMENTS`, `GROUP BY`, `HAVING`, `DECODE/CASE`, `ROUND`, `NVL` |
| 5.2 | No-show & cancellation: rate by department and weekday, donut + trend line | `TO_CHAR(date,'DY')`, correlated subquery, `UNION ALL` for combined trend, `MINUS` sanity check |
| 5.3 | Supporting views | `V_DOCTOR_UTILISATION`, `V_NO_SHOW_ANALYSIS`, `V_TODAY_QUEUE` |
| 5.4 | Showcase page | one page listing where each SQL/PL/SQL concept is demonstrated |

**Exit criteria:** both reports react to a date-range filter and match the package's own numbers.
**Risk:** divide-by-zero → `NULLIF(...,0)`.

---

## Phase 6 — Concurrency proof, quality, demo (Day 14 second half – Day 15 · ~4 h)

| Step | Activity | Evidence |
|---|---|---|
| 6.1 | Double-booking test: two Postman runners hit a capacity-1 slot simultaneously | one `201`, one `409`, screenshot + exported run |
| 6.2 | UB: hold expiry → seat returns to availability | before/after availability output |
| 6.3 | UB: no-show sweep frees the seat | scheduler run log + slot counter before/after |
| 6.4 | Error-log proof: force a failure, show autonomous row survives | SQL output |
| 6.5 | Concept-mapping document (every SQL/PL/SQL concept → file + line/object) | `docs/concept-coverage.md` |
| 6.6 | README: setup order, screenshots, API table, demo script | root `README.md` |
| 6.7 | Demo rehearsal: 8-minute script, reset seed data beforehand | `docs/demo-script.md` |

**Exit criteria:** a stranger can clone the repo, run the scripts in order, and reproduce the 409 proof.
**Risk:** live demo failure → keep a recorded run of the concurrency test as fallback.

---

## Critical path & sequencing rules

```
Phase 0 → Phase 1 (DDL) → Phase 2 (package) → Phase 3 (ORDS) → Phase 4 (APEX) → Phase 5 (reports) → Phase 6
                              │                   │
                              └── seed/verify ────┘  (APEX cannot start before package procedures exist)
```

- Phase 4 pages P2/P3/P5/P6 are **blocked** until 3.4–3.7 exist (or until the equivalent package calls are proven from SQL Workshop).
- Phase 5 is blocked until real appointments exist — run a data-generation step (spread appointments across 4 weeks, deliberately include no-shows) before building charts, otherwise every chart is empty during the demo.
- Phase 6 cannot compress into Day 15 alone; keep the Postman collection updated as each endpoint lands.

## If time runs short, cut in this order

1. Faceted search on P1 → plain search bar.
2. P4 download-slip PDF → print stylesheet only.
3. Stretch items (tele-consult flag, SMS log, e-prescription) → drop entirely.
4. Never cut: capacity guard, 409 proof, no-show sweep, utilisation report.

## Definition of done

- [ ] 10 tables, constraints, indexes, sequences, audit triggers, ≥ 50 seed rows
- [ ] `GIRISH_OPD_PKG` compiles clean; 8 public units; errors logged autonomously
- [ ] 8 ORDS endpoints; Postman collection with 10+ assertions, exported and green
- [ ] 8 APEX pages, role-based authorization, medical-blue theme, mobile OK
- [ ] 2 reports + 3 supporting views
- [ ] Double-booking 409 proven; no-show release proven; hold expiry proven
- [ ] `docs/`: architecture, process flow, ER, concept coverage, demo script
- [ ] Git history shows work spread across the phase days, not one dump
