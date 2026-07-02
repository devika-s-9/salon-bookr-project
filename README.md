[README.md](https://github.com/user-attachments/files/29590218/README.md)
# salon-bookr-project

# SalonBookr — No-Show Reduction Initiative
### Business Analysis Portfolio Project

**Document versions:** BRD v2.0 · FRD v2.0 · See each document's Revision History for the v1.0 → v2.0 scope change.

---

## The Problem

Beauty salons on the **SalonBookr** platform lose an estimated **40% of their booked revenue** to appointment no-shows — customers who forget, cancel last-minute, or simply don't show up. When a slot goes empty, a salon loses the service revenue, and cascading delays frustrate every customer waiting behind it.

No single feature fixes this. The problem has multiple causes, and the solution needs to address them without forcing anything on the customer.

---

## The Solution

This initiative introduces three new modules to the SalonBookr SalonOS platform, each targeting a different root cause of the no-show problem:

| Feature | Channel | What it solves |
|---|---|---|
| **Appointment Reminders** | WhatsApp | Customers forgetting appointments |
| **Live Delay Tracker** | WhatsApp | Customers blindsided by running salon delays |
| **Pre-Payment (Optional)** | Razorpay | Low booking commitment — solved with incentive, not requirement |

Together, these features are designed to reduce the average no-show rate from **40% → 30%** within six months of rollout.

> **Note on scope evolution:** This project originally scoped a "Waitlist Management" feature (queueing customers for cancelled slots). Based on revised business direction, that feature was redefined into the **Live Delay Tracker**, which manages delay on appointments customers have already booked rather than re-filling cancelled ones. Pre-payment was also redefined from a salon-mandated requirement into a fully elective, incentive-driven choice (discount + priority service). Both changes are reflected consistently across every document below — a deliberate part of this portfolio piece is showing how a BA absorbs a material scope change without leaving stale artifacts behind.

---

## Deliverables

```
📁 SalonBookr — No-Show Reduction Initiative
│
├── 🌐 index.html — Portfolio Hub (start here)
│     Single-page case study consolidating every artifact below,
│     with inline previews of the process flows and wireframes
│
├── 📄 BRD — Business Requirements Document (v2.0)
│     Business problem, objectives, stakeholders,
│     12 business requirements, KPIs, scope, risks, revision history
│
├── 📄 FRD — Functional Requirements Document (v2.0)
│     35 FR-numbered requirements, message specs, process flows,
│     state transitions, acceptance criteria, NFRs, open questions
│
├── 📊 RTM — Requirements Traceability Matrix
│     Every business requirement traced to its functional
│     requirements, acceptance criteria, and test case ID
│
├── ✅ UAT Test Cases (19 cases)
│     Preconditions, steps, and expected results per test case,
│     including edge cases (late booking, decline, payment failure)
│     and 3 cross-feature interaction tests
│
├── 🖼️  Process Flow Diagrams (AS-IS / TO-BE)
│     Visual comparison of the current vs proposed
│     appointment journey, mapped to root causes
│     (available as .html, .png, and .pdf)
│
├── 🖥️  Wireframes (5 screens)
│     Lo-fidelity screens annotated to FRD requirements:
│     Booking · Reminder · Delay Tracker · Payment · Settings
│     (available as .html, .png, and .pdf)
│
└── 📋 Résumé (Devika Sardesai — Business Analyst)
```

---

## Process Flows

### AS-IS (Current State)
```
Customer books → Slot allocated → [No reminders] → [No delay visibility] → Day arrives
                                                                                  │
                                                                  ┌───────────────┴───────────────┐
                                                             Shows up                    Doesn't show up
                                                                  │                              │
                                                           Service runs                  Slot goes empty
                                                                                          Revenue lost ❌
                                                                                          No recovery path
```

### TO-BE (Proposed State)
```
Customer books → Pre-pay for discount + priority? (elective, never required)
                       ├── Yes → Razorpay checkout → Discount shown → Priority Service tagged
                       └── No  → Standard booking, no payment
                                          │
                                          ▼
                              Appointment confirmed
                                          │
                                          ▼
                       Reminder sequence (WhatsApp)
                       Confirmation → 24h → 2h → 1h → [30min optional]
                                          │
                                          ▼
                       Live Delay Tracker begins at T-2h
                       Every 30 min (T-2h→T-1h) → every 15 min (T-1h→0)
                       (merged with 2h/1h reminders — no duplicate messages)
                                          │
                              Cumulative delay > 60 min?
                                  ├── Yes → Reschedule offered → New slot, old slot released ✅
                                  └── No  → Continues (Priority customers: minimal/no delay)
                                          │
                                          ▼
                                  Customer shows up?
                                  ├── Attends → Service runs ✅
                                  └── Cancels/No-show → Slot released back to calendar
```

---

## Wireframes

Five lo-fidelity screens covering the complete customer and salon owner journey:

| Screen | Actor | Feature | Key FR |
|---|---|---|---|
| 1 — Book Appointment | Customer | Booking + elective pre-pay choice | FR-3.1, FR-3.2 |
| 2 — Reminder + Delay Status | Customer | Reminder merged with first Delay Tracker update | FR-1.11, FR-2.3, FR-2.11 |
| 3 — Live Delay Tracker | Customer | Escalating delay updates + reschedule offer | FR-2.3, FR-2.4, FR-2.6 |
| 4 — Pre-Payment Checkout | Customer | Discount + Priority Service (optional path) | FR-3.4, FR-3.9, FR-3.10 |
| 5 — Salon Settings | Salon Owner | Delay cadence + discount configuration | FR-2.2, FR-3.1, FR-3.9 |

---

## Traceability & Testing

Every business requirement in the BRD decomposes into functional requirements in the FRD, which are proven out by a specific UAT test case — tracked end to end in the **Requirements Traceability Matrix**.

| Artifact | Coverage |
|---|---|
| Business Requirements | 12 (BR-1 – BR-12) + 2 cross-feature rules (CF-1, CF-2) |
| Functional Requirements | 35 (FR-1.1 – FR-3.13), 100% traced in the RTM |
| UAT Test Cases | 19 — Reminder System (5), Live Delay Tracker (6), Pre-Payment System (5), Cross-Feature (3) |

Sample trace: `BR-7` (offer reschedule past 60-min delay) → `FR-2.6, FR-2.7, FR-2.8` → `TC-007, TC-008, TC-018` (option appears, accept releases slot, decline keeps updates coming).

One FR (FR-3.12, backend scheduling-engine prioritization) is intentionally excluded from the UAT suite and instead flagged for system/integration testing — it isn't customer-observable through WhatsApp or the UI, so a UAT case for it would be artificial. The RTM notes this explicitly rather than forcing a fake test case.

Test case status reads "Ready for Execution," not "Passed" — SalonBookr is a documentation-only case study with no live system, so nothing has actually been executed against real software.

---

## Tech Stack (Integration Layer)

| Component | Technology |
|---|---|
| Messaging | WhatsApp Business API |
| Payment Gateway | Razorpay |
| Platform | SalonBookr SalonOS (B2B SaaS) |
| CRM | SalonBookr internal CRM module |
| Analytics | SalonBookr Analytics Engine |

> This is a BA/Product project. The tech stack reflects integration dependencies identified during requirements elicitation — not code written as part of this project.

---

## KPIs & Success Metrics

| Metric | Baseline | Target | Timeframe |
|---|---|---|---|
| **No-Show Rate** (Primary) | 40% | 30% | 6 months post-launch |
| Reminder Engagement Rate | — | 60% | — |
| Appointment Attendance Rate | — | +10% increase | — |
| Delay Update Delivery Rate | — | 95% | — |
| Reschedule-via-Delay Rate | — | 70% | Of appointments crossing 60-min threshold |
| Pre-Payment Adoption Rate | — | 55% | Elective, incentive-driven |
| Priority Service On-Time Rate | — | 90% | — |

Formula: `No-Show Rate = (Missed Appointments ÷ Total Appointments) × 100`

---

## Business Impact

If the no-show rate drops from 40% to 30%, a salon doing **50 appointments/week at ₹800 average** would recover approximately:

```
Current losses:  50 × 40% × ₹800 = ₹16,000 / week lost to no-shows
Target losses:   50 × 30% × ₹800 = ₹12,000 / week

Weekly recovery: ₹4,000
Annual recovery: ~₹2,08,000 per salon
```

At scale across thousands of salons on the SalonBookr platform, the compounding effect on platform GMV is material.

---

## What This Project Demonstrates

- **BRD vs FRD separation** — understanding which requirements belong at which level, and why mixing them creates document debt
- **Root cause thinking** — the problem isn't "no-shows." It's separate causes (forgetfulness, blind-sided delays, low commitment) each requiring a different intervention
- **Adapting to scope change cleanly** — when the business redirected the waitlist feature into a delay-tracking feature, and made pre-payment elective instead of mandatory, every downstream artifact (BRD, FRD, RTM, UAT, diagrams, wireframes) was updated consistently rather than left half-stale
- **Full traceability, not just terminology overlap** — every one of the 35 functional requirements in the FRD is traced through the RTM to a specific UAT test case; nothing is orphaned, and the one requirement that genuinely can't be UAT-tested (backend scheduling logic) is explicitly flagged as such rather than skipped silently
- **Test-mindedness** — 19 UAT test cases, including edge cases a first pass often misses (late bookings, declined offers, failed payments) that only surfaced by systematically checking FR coverage against the test suite
- **Cross-feature design** — the Reminder System and Live Delay Tracker share trigger points and are explicitly merged to avoid spamming the customer; this kind of seam is easy to miss and is called out as its own cross-feature rule
- **Scope discipline** — explicit non-goals (no guaranteed zero-delay SLA, no mandatory pre-payment) prevent scope creep before it starts
- **Ops readiness** — the BRD includes a pre-launch checklist covering Product, Analytics, Sales, and Customer Success, because documentation is only half the job

---

## Project Structure

```
/
├── index.html                          — Portfolio hub (open this first)
├── SalonBookr_BRD.docx                 — Business Requirements Document (v2.0)
├── SalonBookr_FRD.docx                 — Functional Requirements Document (v2.0)
├── SalonBookr_RTM.xlsx                 — Requirements Traceability Matrix
├── SalonBookr_UAT_Test_Cases.xlsx      — UAT test suite (19 cases)
├── process_flows.html / .png / .pdf    — AS-IS / TO-BE process flow diagrams
├── wireframes.html / .png / .pdf       — Lo-fi wireframes (5 screens)
├── Devika_Sardesai_Business_Analyst.docx — Résumé
└── README.md                           — This file
```

---

## About

**Role:** Business Analyst  
**Domain:** B2B SaaS · Beauty & Wellness · Appointment Management  
**Tools used:** SalonBookr platform context, WhatsApp Business API, Razorpay, standard BA documentation frameworks (BRD + FRD)  

This is a portfolio project built to demonstrate end-to-end BA practice: problem framing, requirements separation, process mapping, low-fidelity wireframing, and clean handling of a real mid-project scope change.
