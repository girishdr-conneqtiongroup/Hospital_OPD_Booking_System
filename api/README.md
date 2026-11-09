# API Layer — ORDS `girish.opd.api`

The 10 `GIRISH_` tables are now published as a REST API. No Node/Python middleware: ORDS maps
HTTP straight onto PL/SQL/SQL in `NOV_2026_BATCH`.

| File | Purpose |
|---|---|
| `01_ords_module.sql` | Creates the whole module (module → templates → parameters → handlers) in one run |
| `postman_collection.json` | Importable Postman collection: 14 requests, 3 negative tests, ids chained through variables |

---

## 1. Publish it

1. **SQL Workshop → SQL Scripts → Create**, paste `01_ords_module.sql`, **Run**.
   Expect **1 statement processed, 1 successful, 0 errors** (the file is one PL/SQL block, closed by `/`).
2. **SQL Workshop → RESTful Services** → open `girish.opd.api`.
   The page shows the published **base URL**. It is normally:

```
https://<your-adb-host>/ords/<schema>/girish/opd/v1/
```

3. Click a handler → **Test**. Without Postman, a browser can GET:
   `.../girish/opd/v1/ping` → `{"status":"ok",...}`

If step 1 fails with `ORA-01031` / `ORA-06550` on `ORDS.*`, the schema is not ORDS-enabled.
Either run once as ADMIN:
`EXEC ORDS_ADMIN.ENABLE_SCHEMA(p_schema => 'NOV_2026_BATCH');`
or build the module in **RESTful Services → Modules → Create Module** and paste the same
SQL/PL-SQL sources into the handlers.

---

## 2. Endpoints

Base path: `/girish/opd/v1`

| # | Method | URI | Purpose | Success | Failure |
|---|---|---|---|---|---|
| 1 | GET | `/ping` | health check, DB user + server time | 200 | — |
| 2 | GET | `/departments/` | departments + doctor count, min/max fee | 200 | — |
| 3 | GET | `/doctors/?dept_id=&q=` | doctor search by department or name | 200 | — |
| 4 | GET | `/availability/?doc_id=&date=YYYY-MM-DD` | free slots + `seats_left` (defaults to today) | 200 | — |
| 5 | POST | `/patients/` | create a patient (dummy-data entry) | 201 | 400, 409 duplicate |
| 6 | POST | `/admin/slots/generate` | weekly templates → dated slots (idempotent) | 201 | 400 |
| 7 | POST | `/appointments/` | **hold** a slot for 5 minutes | 201 | 400, 404, **409 sold out** |
| 8 | POST | `/appointments/confirm` | hold → CONFIRMED + payment row | 200 | 404, 409 expired/not held |
| 9 | GET | `/appointments/:reference` | status, doctor, room, token | 200 | 404 |
| 10 | PUT | `/appointments/cancel` | cancel with rule-based refund | 200 | 400 window closed, 404, 409 |
| 11 | GET | `/admin/appointments/?status=&date=&doctor_id=` | filterable desk list | 200 | — |

All list responses are ORDS collections: `{ "items": [ ... ], "hasMore": false }`.

---

## 3. Request / response examples

**Create patient**

```json
POST /patients/
{ "uhid":"UHID-1001", "full_name":"Ravi Test", "gender":"M",
  "phone":"9876500001", "email":"ravi@example.com", "blood_group":"O+", "dob":"1990-05-14" }

201 → { "status":"CREATED", "patient_id":1, "uhid":"UHID-1001", "full_name":"Ravi Test" }
```

**Generate slots** (needs `GIRISH_SLOT_TEMPLATES` rows for those weekdays)

```json
POST /admin/slots/generate
{ "from_date":"2026-11-09", "to_date":"2026-11-22" }

201 → { "status":"GENERATED", "slots_created":96, "from_date":"2026-11-09", "to_date":"2026-11-22" }
```

**Book (hold)**

```json
POST /appointments/
{ "slot_id":12, "patient_id":1 }

201 → { "status":"HELD", "reference":"OPD-202611-01024",
        "appointment_id":5, "slot_id":12, "consult_fee":500, "hold_expires_in":"5 minutes" }

409 → { "status":"CONFLICT", "message":"Slot is fully booked", "slot_id":12 }
```

**Confirm**

```json
POST /appointments/confirm
{ "reference":"OPD-202611-01024", "payment_mode":"UPI" }

200 → { "status":"CONFIRMED", "reference":"OPD-202611-01024",
        "payment_mode":"UPI", "amount":500, "txn_ref":"TXN-20261109153012-5" }
```

**Cancel**

```json
PUT /appointments/cancel
{ "reference":"OPD-202611-01024", "reason":"Patient unwell" }

200 → { "status":"CANCELLED", "hours_before":26.4, "refund_percent":100,
        "refund_amount":500, "penalty_amount":0 }

400 → { "status":"BAD_REQUEST", "message":"Cancellation window closed: slot has already started" }
```

---

## 4. Run the Postman collection

0. Before the first run, load master data: `database/03_bootstrap_seed.sql`
   (6 departments, 4 doctors, 15 weekly templates, 4 patients, 3 refund rules).
   Without at least one template, `/admin/slots/generate` returns `slots_created: 0`
   and `/availability` is empty — that is not an API bug.
1. Postman → **Import** → `postman_collection.json`.
2. Edit the collection variable `base_url` to the URL from the module page.
3. **Run collection** (or send 01 → 14 in order). Variables chain automatically:
   `patient_id` from request 04, `slot_id` from 06, `reference` from 07.
4. Negative tests must fail on purpose: `12 → 404`, `13 → 404`, `14 → 400`.

### Concurrency proof (the 100-mark demo)

1. Take a slot whose `max_capacity` is 1 (`availability` shows `max_capacity: 1`).
2. Duplicate request **07** into two folders, or run **Collection Runner** with **2 iterations** and
   **0 delay**.
3. Result: exactly one `201`, exactly one `409 Slot is fully booked`.
   That is `SELECT … FOR UPDATE` + the capacity check working; no double booking is possible.

---

## 5. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `404 Not Found` from ORDS on every call | Wrong base URL — copy it from **RESTful Services → module page**, and check the trailing `/` on the template |
| `ORA-00942: table or view does not exist` | The DDL was run in a different schema, or FILE 01 was not run |
| `ORA-00904: invalid identifier "..."` | A column name changed after the module was created — re-run `01_ords_module.sql` (it drops and recreates the module) |
| `ORA-01031: insufficient privileges` | Schema not ORDS-enabled (see §1) |
| `PGRST`/`400` on POST | Body must be raw JSON with `Content-Type: application/json` |
| Second booking returns `201` on a capacity-1 slot | `current_bookings` was edited by hand outside the API; reset it and use only the endpoints |
| `409` on confirm | The 5-minute hold expired — book again (that is the intended safety behaviour) |

---

## 6. What changes when the PL/SQL package arrives

Handlers 5–10 currently contain inline SQL/PL-SQL, because `GIRISH_OPD_PKG` does not exist yet.
When it is built, only the **handler source** changes:

```plsql
-- before: 30 lines of locking + insert + update
-- after:
GIRISH_OPD_PKG.HOLD_SLOT(p_slot_id => :slot_id, p_patient_id => :patient_id,
                         o_booking_ref => l_ref, o_status => l_status, o_msg => l_msg);
```

The URIs, JSON and status codes stay identical, so the Postman collection keeps working — and the
APEX screens can call either layer with the same results.
