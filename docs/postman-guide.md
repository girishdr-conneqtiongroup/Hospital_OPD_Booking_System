# Postman Guide — load dummy data and verify every endpoint

For the GIRISH OPD API (`girish.opd.api`, base path `/girish/opd/v1/`).

**Precondition:** `api/01_ords_module.sql` must have been run **after** the admin endpoints were
added (it now contains `/admin/departments/`, `/admin/doctors/`, `/admin/templates/`). Re-run it any
time — it drops and recreates the module.

---

## 1. One-time setup

| Step | Where | Action |
|---|---|---|
| 1 | Postman | **Import** → File → `api/postman_collection.json` → Import |
| 2 | APEX | SQL Workshop → RESTful Services → `girish.opd.api` → copy the base URL |
| 3 | Postman | Click the collection → **Variables** tab → paste the URL into `base_url` → Save (Ctrl+S) |
| 4 | Postman | Send **01 Ping**. Green `200` + `{"status":"ok"}` means the wiring is correct |

Base URL looks like `https://<adb-host>/ords/<schema>/girish/opd/v1`
(no trailing slash; the collection adds `/ping`, `/departments/`, …).

---

## 2. Load dummy data in this order

Each request is **one row per call with its own COMMIT** — the undo-friendly path when a big SQL
script fails with `ORA-30036`.

| # | Request | Body | Expected |
|---|---|---|---|
| 1 | `03a Create department` | `{"dept_code":"CARD","dept_name":"Cardiology","floor_no":2}` | `201` + `dept_id` |
| 2 | `03b Create doctor` | `{"dept_code":"CARD","emp_code":"EMP-1001","full_name":"Dr. Ananya Sharma","qualification":"MD DM","email":"ananya.sharma@opd.local","phone":"9845010001","room_no":"C-201","consult_fee":800,"languages":"English,Hindi"}` | `201` + `doctor_id` |
| 3 | `03c Create slot template` | `{"doctor_id":{{doctor_id}},"all_weekdays":true,"start_time":"09:00","end_time":"11:00","slot_minutes":15,"max_patients":2}` | `201` + `templates_created: 5` |
| 4 | `04 Create patient` | `{"uhid":"UHID-1001","full_name":"Ravi Test","gender":"M","phone":"9876500001","blood_group":"O+"}` | `201` + `patient_id` |
| 5 | `05 Generate slots` | `{"from_date":"2026-11-09","to_date":"2026-11-22"}` | `201` + `slots_created` > 0 |
| 6 | `06 Availability` | — | `200`, `items[]` with `seat_left` |
| 7 | `07 Book slot` | `{"slot_id":{{slot_id}},"patient_id":{{patient_id}}}` | `201` + `reference` |
| 8 | `08 Confirm booking` | `{"reference":"{{reference}}","payment_mode":"UPI"}` | `200` + `txn_ref` |
| 9 | `09 Get by reference` | — | `200` with doctor, room, status |
| 10 | `10 Admin list` | — | `200`, `items[]` |
| 11 | `11 Cancel` | `{"reference":"{{reference}}","reason":"Patient unwell"}` | `200` + `refund_amount` |

Ids chain automatically: `doctor_id` (03b) → `slot_id` (06) → `reference` (07). Nothing to copy by hand.

**Adding more rows:** change `emp_code`, `email` and `phone` on each repeat — those columns are
UNIQUE, so a second identical call correctly returns `409`.

---

## 3. Five ways to check a response

| Method | How | What it proves |
|---|---|---|
| Status + body | Send, read **Status: 201 Created** and the **Body → Pretty** tab | The contract works |
| **Tests tab** | Each request already has `pm.test(...)` | Green ticks = assertions passed; red = which one failed |
| **Console** | View → Show Postman Console (**Ctrl+Alt+C**) | Exact URL, headers, request body, response, `console.log` output |
| **Test Results tab** | Appears after Collection Runner | Pass/fail count for the whole run |
| **Save response** | Response → **Save** → Save as example | Permanent evidence for your report |

Extra checks:

- **Copy as cURL** — request → `</>` **Code snippet** → cURL → paste in a terminal. Proves the API is
  not Postman-specific.
- **Browser GET** — paste `.../girish/opd/v1/ping` or `.../departments/` in Chrome. GETs need no tool.
- **Database check** — SQL Workshop → SQL Commands:
  ```sql
  SELECT booking_ref, status, consult_fee, booked_at FROM girish_appointments ORDER BY appointment_id DESC;
  SELECT slot_id, current_bookings, max_capacity, status FROM girish_slots WHERE current_bookings > 0;
  SELECT * FROM girish_error_log ORDER BY error_id DESC;
  ```

---

## 4. Building a request by hand (all tabs)

Take **07 Book slot** as the model: method `POST`, URL `{{base_url}}/appointments/`.

| Tab / control | Purpose | For this API |
|---|---|---|
| Method dropdown | GET / POST / PUT / PATCH / DELETE / HEAD / OPTIONS | We use GET, POST, PUT |
| **Params** | query string (`?doc_id=1&date=2026-11-10`) or **path variables** (`:reference`) | `doctors`, `availability`, `admin/appointments`, `appointments/:reference` |
| **Authorization** | none / Basic / Bearer / API key | none — the module is public |
| **Headers** | `Content-Type: application/json` | set automatically when Body = raw + JSON |
| **Body → raw → JSON** | the only body mode this API accepts (handlers parse `:body` with `JSON_VALUE`) | all POST/PUT |
| Body → form-data / x-www-form-urlencoded | would send `key=value`, not JSON → handlers return `400` | **not used** |
| Body → binary / GraphQL | file upload / GraphQL | **not used** |
| **Scripts → Pre-request** | runs before sending | e.g. stamp today's date |
| **Scripts → Tests** | assertions + saving variables | already in the collection |
| **Settings** | disable SSL verification, timeouts | leave default; ADB has a valid certificate |

Useful snippet — dynamic date in a pre-request script:

```js
const d = new Date();
const iso = d.toISOString().slice(0, 10);
pm.collectionVariables.set('today', iso);
```

Then send `"from_date": "{{today}}"`.

---

## 5. Variables: four scopes, when to use which

| Scope | Set in | Lifetime | Used here for |
|---|---|---|---|
| Local | `pm.variables.set('x', 1)` | that request only | temporary values |
| Collection | Variables tab / `pm.collectionVariables.set()` | shared by all requests | `base_url`, `doctor_id`, `patient_id`, `slot_id`, `reference` |
| Environment | Environments → new → add key → select top-right | switchable sets | `base_url` for dev vs demo, tokens |
| Global | Environments → Globals | everything | avoid — hidden state |

Recommended: keep `base_url` in an **Environment** (`OPD-DEV`), everything else in collection
variables. Then one dropdown switches the whole collection between workspaces.

---

## 6. Negative and concurrency tests

**Negative (folder `02 Negative tests`)**

| Request | Expected |
|---|---|
| 12 Invalid reference | `404` `{"status":"NOT_FOUND"}` |
| 13 Missing slot | `404` |
| 14 Bad gender `"X"` | `400` (or `409` if `uhid`/`phone` already exist) |

Also worth sending by hand:
- Book the same slot and patient until capacity is reached → last call `409`.
- Confirm a second time → `409 "Only a HELD booking can be confirmed"`.
- Cancel twice → `409`.
- Cancel a slot that already started → `400 "Cancellation window closed"`.
- Send an empty body `{}` → `400`, never `500`.

**Concurrency (the double-booking proof)**

1. Find a slot with `max_capacity: 1` in **06 Availability** (repeat **03c** with `"max_patients":1`
   if needed).
2. Duplicate request **07** into a second folder, or right-click → **Duplicate**.
3. Collection → **Run** → select the two requests → **Iterations: 2**, **Delay: 0** → Run.
4. Result: exactly one `201` and exactly one `409 Slot is fully booked`.
   That is `SELECT … FOR UPDATE` + the capacity check doing its job.

**Runner options that matter:** Iterations, Delay, Data (CSV/JSON for bulk dummy data), Save
responses, and "Persist variable changes" (so `reference` survives between iterations).

---

## 7. Bulk dummy data with the Runner (optional)

Create `patients.csv`:

```
uhid,full_name,gender,phone
UHID-2001,Test One,M,9876500101
UHID-2002,Test Two,F,9876500102
```

Body of `04 Create patient` becomes:

```json
{ "uhid": "{{uhid}}", "full_name": "{{full_name}}", "gender": "{{gender}}", "phone": "{{phone}}" }
```

Runner → Data → select the CSV → Preview → Run. Postman issues one request per row, in order.

---

## 8. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `404` on every URL | Wrong `base_url`; copy it again from the module page. Keep the trailing `/` on templates |
| `400` with `"BAD_REQUEST"` | Body is not raw JSON, or a required field is missing (`slot_id`, `patient_id`, `reference`, `emp_code`, …) |
| `404` from your own handler | The referenced row does not exist (slot/patient/reference) |
| `409` on create | A UNIQUE column already has that value — change `emp_code` / `email` / `phone` |
| `500` | Check `SELECT * FROM girish_error_log ORDER BY error_id DESC` — the ORA stack is in `ERROR_MESSAGE` |
| `ORA-30036 unable to extend … in undo tablespace` | The workspace's undo space is exhausted by large scripts. Use one-row Postman calls (each commits), or retry with a short date range on `05 Generate slots` |
| `ORA-01031` when running the module script | Schema not ORDS-enabled → build the module in RESTful Services UI, or ask ADMIN |
| `slots_created: 0` | No templates for those weekdays, or the date range is in the past — run **03c** first |
| `409` on confirm | The 5-minute hold expired — book again |
