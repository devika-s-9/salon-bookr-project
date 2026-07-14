# SalonBookr — No-Show Reduction Initiative
### Business Analysis / Product Management Portfolio Project

**Document versions:** BRD v2.0 · FRD v2.0 · PRD v1.0 (see Revision History in each doc for the v1.0 → v2.0 scope change)

---

## The Problem

Beauty salons on the **SalonBookr** platform lose an estimated **40% of booked revenue** to appointment no-shows — customers who forget, cancel last-minute, or simply don't show up.

## The Solution

Three modules on the SalonBookr SalonOS platform, each targeting a different root cause:

| Feature | Channel | Solves |
|---|---|---|
| **Appointment Reminders** | WhatsApp | Customers forgetting appointments |
| **Live Delay Tracker** | WhatsApp | Customers blindsided by running delays |
| **Pre-Payment (Optional)** | Razorpay | Low booking commitment — incentive, not requirement |

Target: reduce no-show rate from **40% → 30%** within six months of rollout.

> **Scope note:** originally scoped as a "Waitlist Management" feature + mandatory pre-payment. Revised (v2.0) into the Live Delay Tracker (manages delay on booked appointments) and fully elective pre-payment (discount + priority service). Reflected consistently across every artifact below.

---

## Deliverables

| File | What it is |
|---|---|
| `SalonBookr_BRD.pdf` | Business Requirements — problem, objectives, KPIs, scope, risks |
| `SalonBookr_FRD.pdf` | Functional Requirements — FR-numbered behavior, process flows, message specs, state transitions |
| `SalonBookr_PRD.pdf` | Product Requirements — synthesizes BRD + FRD into a single build/planning reference |
| `SalonBookr_RTM.xlsx` | Requirements Traceability Matrix — BR → FR → test case coverage |
| `SalonBookr_UAT_Test_Cases.xlsx` | 19-case UAT suite mapped to functional requirements |
| `process_flows.png` | AS-IS vs TO-BE customer journey diagrams |
| `wireframes.png` | 5 lo-fi screens annotated to FRD requirement numbers |
| `SalonBookr_TSQL.sql` | Analytics backend — 6-table schema + 12 reporting views + refresh procs |
| `SalonBookr_Analytics_Dashboard.pbit` | Power BI dashboard template built on the SQL views |
| `salonbookr_powerbi_replica.html` | Interactive HTML replica of the Power BI dashboard |
| `salonbookr_product_metrics.html` | Product metrics dashboard — North Star, KPIs, funnel, drop-off, risks |

---

## KPIs

| Metric | Baseline | Target |
|---|---|---|
| No-Show Rate (Primary) | 40% | 30% in 6 months |
| Reminder Engagement Rate | — | 60% |
| Delay Update Delivery Rate | — | 95% |
| Reschedule-via-Delay Rate | — | 70% |
| Pre-Payment Adoption Rate | — | 55% |
| Priority Service On-Time Rate | — | 90% |

## Tech Stack

WhatsApp Business API · Razorpay · SQL Server / Azure SQL · Power BI · SalonBookr SalonOS (B2B SaaS)

---

## What This Demonstrates

- **BRD → FRD → PRD layering** and requirements traceability (BR → FR → UAT)
- **Root cause thinking** — three distinct causes, three distinct interventions
- **Clean scope-change handling** — a mid-project pivot reflected consistently across every downstream artifact
- **Cross-feature design** — reminders and delay updates merged to avoid duplicate messaging
- **End-to-end analytics** — from raw SQL schema/views to a Power BI dashboard and product metrics view
- **Ops readiness** — pre-launch checklist across Product, Analytics, Sales, and Customer Success

---

## About

**Role:** Business Analyst / Product  
**Domain:** B2B SaaS · Beauty & Wellness · Appointment Management  
**Tools:** SalonBookr platform context, WhatsApp Business API, Razorpay, SQL, Power BI, standard BA/PM documentation frameworks (BRD, FRD, PRD)

Portfolio project demonstrating end-to-end BA/PM practice: problem framing, requirements definition across three document layers, process mapping, wireframing, traceability, UAT, and analytics/dashboard delivery.
