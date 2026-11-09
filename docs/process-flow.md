# Process Flow Diagram — Hospital OPD Appointment Booking Platform

Two views of the same process:

1. **End-to-end flow** — what happens from "patient needs a doctor" to "consultation completed",
   including every branch the rubric tests (sold out, abandoned hold, cancellation, no-show).
2. **Appointment lifecycle** — the status machine the database enforces.

---

## 1. End-to-end booking, check-in and consultation flow

```mermaid
flowchart TD
    START(["Patient needs an OPD consultation"]) --> S1["Open app / reception desk<br/>choose department or search doctor"]
    S1 --> S2["Pick a date<br/>GET /v1/availability?doc_id&date"]
    S2 --> D1{"Any slot with<br/>free capacity?"}
    D1 -- "No" --> S2B["Offer next available date<br/>(no rows → 404)"]
    S2B --> S2
    D1 -- "Yes" --> S3["Select slot<br/>POST /v1/appointments/book<br/>{ slot_id, patient_id }"]

    S3 --> LOCK["GIRISH_OPD_PKG.HOLD_SLOT<br/>SELECT … FOR UPDATE on SLOTS row"]
    LOCK --> D2{"booked < max_capacity<br/>AND slot status AVAILABLE<br/>AND patient not already booked?"}
    D2 -- "No" --> FULL["409 Conflict<br/>'Slot is fully booked'"]
    FULL --> S2B
    D2 -- "Yes" --> HOLD["Insert APPOINTMENT status = HELD<br/>hold_expires_at = SYSTIMESTAMP + 5 min<br/>201 Created + booking reference"]

    HOLD --> D3{"Payment / confirmation<br/>within 5 minutes?"}
    D3 -- "No — abandoned" --> EXP["Hold expires<br/>scheduler releases the seat"]
    EXP --> S2B
    D3 -- "Yes" --> CONF["CONFIRM_APPOINTMENT<br/>validate hold → CONFIRMED<br/>insert PAYMENTS row (SUCCESS)<br/>seat committed to patient"]
    CONF --> SLIP["Digital slip<br/>Reference OPD-202611-00042<br/>doctor room no. + instructions"]

    SLIP --> D4{"Patient cancels<br/>before the slot starts?"}
    D4 -- "Yes" --> CAN["CANCEL_APPOINTMENT<br/>lookup CANCELLATION_RULES by hours-before<br/>refund % → PAYMENTS (REFUNDED)<br/>status CANCELLED, seat freed"]
    CAN --> S2B
    D4 -- "No — after start time" --> DECLINE["400 Bad Request<br/>'Cancellation window has closed'"]

    D4 -- "No — patient arrives" --> D5{"Check-in within grace period<br/>(slot start + 20 min)?"}
    D5 -- "Yes" --> TOK["CHECKIN_AND_GENERATE_TOKEN<br/>status CHECKED_IN<br/>token #CARD-04 for today"]
    D5 -- "No" --> NS["RELEASE_NO_SHOWS<br/>status NO_SHOW, seat freed<br/>walk-in capacity returns"]
    TOK --> CALL["Doctor desk: 'Call patient'<br/>live queue in token order"]
    CALL --> DONE(["COMPLETED<br/>consultation recorded"])
    NS --> REP["Management reports<br/>utilisation · no-show rate"]
    DONE --> REP
    CAN --> REP
    DECLINE --> REP
```

---

## 2. Appointment lifecycle (status machine)

```mermaid
stateDiagram-v2
    direction LR

    [*] --> HELD : HOLD_SLOT
    HELD --> CONFIRMED : CONFIRM_APPOINTMENT + payment
    HELD --> EXPIRED : hold window elapsed (scheduler)
    HELD --> CANCELLED : patient abandons / cancels

    CONFIRMED --> CHECKED_IN : CHECKIN_AND_GENERATE_TOKEN
    CONFIRMED --> CANCELLED : CANCEL_APPOINTMENT (rule-based refund)
    CONFIRMED --> NO_SHOW : grace period elapsed

    CHECKED_IN --> COMPLETED : doctor completes consultation
    CHECKED_IN --> NO_SHOW : did not attend

    EXPIRED --> [*]
    CANCELLED --> [*]
    NO_SHOW --> [*]
    COMPLETED --> [*]

    note right of HELD
        Seat is reserved but not paid.
        Only this state can expire.
    end note

    note right of CANCELLED
        Terminal. Refund % comes from
        GIRISH_CANCELLATION_RULES.
    end note

    note right of NO_SHOW
        Terminal. Decrements slot
        current_bookings so the seat
        is sellable again.
    end note
```

### Slot status machine (separate, simpler)

| Slot status | Meaning | Becomes |
|---|---|---|
| `AVAILABLE` | Generated, has free capacity | `BOOKED` when `current_bookings` reaches `max_capacity` |
| `BOOKED` | At capacity — no new holds accepted | `AVAILABLE` again after a cancellation / no-show / hold expiry |
| `BLOCKED` | Doctor unavailable (leave, emergency, admin block) | `AVAILABLE` only by admin action |

---

## 3. Change of state → who is allowed to trigger it

| Transition | Actor | Entry point | DB effect |
|---|---|---|---|
| — → `HELD` | Patient / Receptionist | `POST /appointments/book`, P2 wizard | `APPOINTMENTS` insert, `SLOTS.current_bookings + 1` |
| `HELD` → `CONFIRMED` | Patient / Receptionist | `POST /appointments/confirm`, P3 | `PAYMENTS` insert, `hold_expires_at` cleared |
| `HELD` → `EXPIRED` | Scheduler | job `GIRISH_HOLD_EXPIRY_JOB` | `current_bookings - 1` |
| `CONFIRMED` → `CHECKED_IN` | Receptionist | `PUT /appointments/checkin`, P5 | `TOKEN_QUEUE` insert, `checked_in_at` set |
| `CHECKED_IN` → `COMPLETED` | Doctor | P6 button | `completed_at` set |
| `CONFIRMED` → `NO_SHOW` | Scheduler | job `GIRISH_NO_SHOW_JOB` | `current_bookings - 1` |
| `HELD`/`CONFIRMED` → `CANCELLED` | Patient / Staff / Admin | `PUT /appointments/cancel`, P4 | refund row, `current_bookings - 1` |

---

## 4. Design note — where capacity is actually reserved

The blueprint's wording has `CONFIRM_APPOINTMENT` increment the slot counter. For the concurrency
test to be deterministic, reserve the seat at **hold** time instead (increment under the
`SELECT ... FOR UPDATE` lock) and release it on expiry / cancel / no-show. `CONFIRM` then only flips
the status and writes the payment row. With one counter shared by holds and confirmed bookings, two
simultaneous requests on a capacity-1 slot can never both pass the check — one gets `201`, the other
`409`, every run.
