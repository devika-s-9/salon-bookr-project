-- ================================================================
-- SalonBookr — Product Analytics T-SQL
-- No-Show Reduction Initiative
-- SQL Server / Azure SQL Database compatible
--
-- Contents:
--   1.  Schema  (6 tables)
--   2.  Indexes
--   3.  Seed / reference data
--   4.  Views  (12 — one per Power BI visual)
--   5.  Stored Procedures (refresh + utility)
--   6.  Power BI dataset query stubs
-- ================================================================

USE SalonBookrAnalytics;
GO

-- ================================================================
-- 1. SCHEMA
-- ================================================================

IF OBJECT_ID('dbo.salons',           'U') IS NULL
CREATE TABLE dbo.salons (
    salon_id         NVARCHAR(36)   NOT NULL CONSTRAINT PK_salons PRIMARY KEY,
    salon_name       NVARCHAR(255)  NOT NULL,
    city             NVARCHAR(100)  NULL,
    plan_tier        NVARCHAR(50)   NOT NULL DEFAULT 'standard',   -- standard | premium
    onboarded_at     DATE           NOT NULL,
    -- Feature toggles (configured per salon)
    reminder_30min   BIT            NOT NULL DEFAULT 0,
    delay_tracker    BIT            NOT NULL DEFAULT 1,
    prepay_enabled   BIT            NOT NULL DEFAULT 0,
    prepay_discount  DECIMAL(5,2)   NOT NULL DEFAULT 10.00,        -- %
    is_active        BIT            NOT NULL DEFAULT 1,
    created_at       DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at       DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF OBJECT_ID('dbo.customers',        'U') IS NULL
CREATE TABLE dbo.customers (
    customer_id      NVARCHAR(36)   NOT NULL CONSTRAINT PK_customers PRIMARY KEY,
    salon_id         NVARCHAR(36)   NOT NULL
                       CONSTRAINT FK_customers_salon
                       REFERENCES dbo.salons(salon_id),
    phone_hash       NVARCHAR(64)   NOT NULL,   -- SHA-256 of E.164 phone
    first_seen       DATE           NOT NULL,
    total_bookings   INT            NOT NULL DEFAULT 0,
    created_at       DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF OBJECT_ID('dbo.appointments',     'U') IS NULL
CREATE TABLE dbo.appointments (
    appointment_id    NVARCHAR(36)   NOT NULL CONSTRAINT PK_appointments PRIMARY KEY,
    salon_id          NVARCHAR(36)   NOT NULL
                        CONSTRAINT FK_appt_salon
                        REFERENCES dbo.salons(salon_id),
    customer_id       NVARCHAR(36)   NOT NULL
                        CONSTRAINT FK_appt_customer
                        REFERENCES dbo.customers(customer_id),
    service_name      NVARCHAR(255)  NULL,
    scheduled_at      DATETIME2      NOT NULL,
    created_at        DATETIME2      NOT NULL,
    -- Status: confirmed | attended | no_show | cancelled | rescheduled
    status            NVARCHAR(30)   NOT NULL,
    -- Payment: not_applicable | pending | successful | failed | expired
    payment_status    NVARCHAR(20)   NOT NULL DEFAULT 'not_applicable',
    is_priority       BIT            NOT NULL DEFAULT 0,
    original_price    DECIMAL(10,2)  NULL,
    discount_pct      DECIMAL(5,2)   NOT NULL DEFAULT 0,
    amount_paid       DECIMAL(10,2)  NULL,
    razorpay_txn_id   NVARCHAR(100)  NULL,
    rescheduled_from  NVARCHAR(36)   NULL
                        CONSTRAINT FK_appt_origin
                        REFERENCES dbo.appointments(appointment_id),
    marked_at         DATETIME2      NULL    -- when attended/no_show recorded
);
GO

IF OBJECT_ID('dbo.reminder_events',  'U') IS NULL
CREATE TABLE dbo.reminder_events (
    event_id          NVARCHAR(36)   NOT NULL CONSTRAINT PK_reminders PRIMARY KEY,
    appointment_id    NVARCHAR(36)   NOT NULL
                        CONSTRAINT FK_rem_appt
                        REFERENCES dbo.appointments(appointment_id),
    -- Type: confirmation | 24h | 2h | 1h | 30min
    reminder_type     NVARCHAR(20)   NOT NULL,
    scheduled_at      DATETIME2      NOT NULL,
    sent_at           DATETIME2      NULL,
    -- delivery_status: sent | failed | skipped | merged
    delivery_status   NVARCHAR(20)   NULL,
    retry_count       SMALLINT       NOT NULL DEFAULT 0,
    -- customer_action: none | reschedule | cancel
    customer_action   NVARCHAR(20)   NULL
);
GO

IF OBJECT_ID('dbo.delay_events',     'U') IS NULL
CREATE TABLE dbo.delay_events (
    event_id          NVARCHAR(36)   NOT NULL CONSTRAINT PK_delays PRIMARY KEY,
    appointment_id    NVARCHAR(36)   NOT NULL
                        CONSTRAINT FK_del_appt
                        REFERENCES dbo.appointments(appointment_id),
    triggered_at      DATETIME2      NOT NULL,
    delay_minutes     INT            NOT NULL,   -- cumulative estimated delay
    -- delay_band: on_schedule | minor | moderate | major
    delay_band        NVARCHAR(20)   NOT NULL,
    message_sent      BIT            NOT NULL DEFAULT 0,
    merged_reminder   BIT            NOT NULL DEFAULT 0,
    reschedule_shown  BIT            NOT NULL DEFAULT 0,
    -- customer_action: none | reschedule | wait
    customer_action   NVARCHAR(20)   NULL
);
GO

-- Date dimension (required for Power BI time intelligence)
IF OBJECT_ID('dbo.dim_date',         'U') IS NULL
CREATE TABLE dbo.dim_date (
    date_key         INT            NOT NULL CONSTRAINT PK_dim_date PRIMARY KEY,  -- YYYYMMDD
    full_date        DATE           NOT NULL,
    day_of_week      TINYINT        NOT NULL,   -- 1=Sun … 7=Sat
    day_name         NVARCHAR(10)   NOT NULL,
    week_number      TINYINT        NOT NULL,
    month_number     TINYINT        NOT NULL,
    month_name       NVARCHAR(10)   NOT NULL,
    quarter          TINYINT        NOT NULL,
    year             SMALLINT       NOT NULL,
    is_weekend       BIT            NOT NULL,
    fiscal_week      INT            NOT NULL    -- weeks since 1-Jan-2025
);
GO

-- ================================================================
-- 2. INDEXES
-- ================================================================

-- appointments — most-queried columns
CREATE NONCLUSTERED INDEX IX_appt_scheduled
    ON dbo.appointments(scheduled_at)
    INCLUDE (status, payment_status, is_priority, salon_id, customer_id);

CREATE NONCLUSTERED INDEX IX_appt_salon_status
    ON dbo.appointments(salon_id, status)
    INCLUDE (scheduled_at, payment_status, amount_paid, discount_pct);

CREATE NONCLUSTERED INDEX IX_appt_customer
    ON dbo.appointments(customer_id)
    INCLUDE (scheduled_at, status, created_at);

-- reminder_events
CREATE NONCLUSTERED INDEX IX_rem_appt
    ON dbo.reminder_events(appointment_id)
    INCLUDE (reminder_type, delivery_status, customer_action, sent_at);

CREATE NONCLUSTERED INDEX IX_rem_sent
    ON dbo.reminder_events(sent_at)
    INCLUDE (delivery_status, reminder_type, customer_action);

-- delay_events
CREATE NONCLUSTERED INDEX IX_del_appt
    ON dbo.delay_events(appointment_id)
    INCLUDE (delay_band, reschedule_shown, customer_action, triggered_at);

-- customers
CREATE NONCLUSTERED INDEX IX_cust_salon
    ON dbo.customers(salon_id)
    INCLUDE (first_seen, total_bookings);
GO

-- ================================================================
-- 3. DATE DIMENSION SEED (2025-01-01 → 2026-12-31)
-- ================================================================

IF NOT EXISTS (SELECT 1 FROM dbo.dim_date WHERE date_key = 20250101)
BEGIN
    DECLARE @start DATE = '2025-01-01';
    DECLARE @end   DATE = '2026-12-31';
    DECLARE @d     DATE = @start;

    WHILE @d <= @end
    BEGIN
        INSERT INTO dbo.dim_date
        SELECT
            CONVERT(INT, FORMAT(@d, 'yyyyMMdd')),
            @d,
            DATEPART(WEEKDAY, @d),
            DATENAME(WEEKDAY, @d),
            DATEPART(WEEK,    @d),
            MONTH(@d),
            DATENAME(MONTH,   @d),
            DATEPART(QUARTER, @d),
            YEAR(@d),
            CASE WHEN DATEPART(WEEKDAY, @d) IN (1,7) THEN 1 ELSE 0 END,
            DATEDIFF(WEEK, '2025-01-01', @d) + 1;
        SET @d = DATEADD(DAY, 1, @d);
    END;
END;
GO

-- ================================================================
-- 4. VIEWS  (Power BI connects to these — never raw tables)
-- ================================================================

-- ── V1: Executive KPI snapshot (single row, refreshes daily) ──
CREATE OR ALTER VIEW dbo.vw_kpi_snapshot AS
WITH base AS (
    SELECT
        a.appointment_id,
        a.status,
        a.payment_status,
        a.is_priority,
        a.salon_id,
        a.scheduled_at,
        a.amount_paid,
        a.discount_pct,
        a.original_price,
        a.marked_at,
        s.prepay_enabled
    FROM dbo.appointments a
    JOIN dbo.salons s ON s.salon_id = a.salon_id
    WHERE a.scheduled_at >= DATEADD(DAY, -30, CAST(SYSUTCDATETIME() AS DATE))
),
reminder_stats AS (
    SELECT
        COUNT(*)                                                             AS total_sent,
        SUM(CASE WHEN delivery_status = 'sent'            THEN 1 ELSE 0 END) AS delivered,
        SUM(CASE WHEN customer_action IS NOT NULL          THEN 1 ELSE 0 END) AS engaged
    FROM dbo.reminder_events re
    JOIN dbo.appointments a ON a.appointment_id = re.appointment_id
    WHERE a.scheduled_at >= DATEADD(DAY, -30, CAST(SYSUTCDATETIME() AS DATE))
),
delay_stats AS (
    SELECT
        COUNT(*)                                                                    AS total_checks,
        SUM(CASE WHEN message_sent = 1                                THEN 1 ELSE 0 END) AS updates_sent,
        SUM(CASE WHEN reschedule_shown = 1                            THEN 1 ELSE 0 END) AS reschedule_offered,
        SUM(CASE WHEN reschedule_shown = 1 AND customer_action = 'reschedule' THEN 1 ELSE 0 END) AS rescheduled
    FROM dbo.delay_events de
    JOIN dbo.appointments a ON a.appointment_id = de.appointment_id
    WHERE a.scheduled_at >= DATEADD(DAY, -30, CAST(SYSUTCDATETIME() AS DATE))
)
SELECT
    -- Primary KPI
    CAST(
        100.0 * SUM(CASE WHEN b.status = 'no_show' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(b.appointment_id), 0)
    AS DECIMAL(5,1))                                                        AS no_show_rate_pct,
    40.0                                                                    AS baseline_pct,
    30.0                                                                    AS target_pct,
    COUNT(b.appointment_id)                                                 AS total_appointments,
    SUM(CASE WHEN b.status = 'no_show'     THEN 1 ELSE 0 END)              AS total_no_shows,
    SUM(CASE WHEN b.status = 'attended'    THEN 1 ELSE 0 END)              AS total_attended,
    SUM(CASE WHEN b.status = 'rescheduled' THEN 1 ELSE 0 END)              AS total_rescheduled,
    -- Reminder KPIs
    rs.total_sent                                                           AS reminders_sent,
    CAST(100.0 * rs.delivered / NULLIF(rs.total_sent, 0) AS DECIMAL(5,1))  AS delivery_rate_pct,
    CAST(100.0 * rs.engaged   / NULLIF(rs.total_sent, 0) AS DECIMAL(5,1))  AS engagement_rate_pct,
    -- Delay KPIs
    CAST(100.0 * ds.updates_sent / NULLIF(ds.total_checks, 0) AS DECIMAL(5,1)) AS delay_delivery_pct,
    CAST(100.0 * ds.rescheduled  / NULLIF(ds.reschedule_offered, 0) AS DECIMAL(5,1)) AS reschedule_via_delay_pct,
    -- Pre-payment KPIs
    CAST(
        100.0 * SUM(CASE WHEN b.payment_status = 'successful' THEN 1 ELSE 0 END)
              / NULLIF(SUM(CASE WHEN b.prepay_enabled = 1 THEN 1 ELSE 0 END), 0)
    AS DECIMAL(5,1))                                                        AS prepay_adoption_pct,
    -- Priority KPI
    CAST(
        100.0 * SUM(CASE WHEN b.is_priority = 1
                          AND b.status = 'attended'
                          AND DATEDIFF(MINUTE, b.scheduled_at, b.marked_at) <= 5
                         THEN 1 ELSE 0 END)
              / NULLIF(SUM(CASE WHEN b.is_priority = 1 THEN 1 ELSE 0 END), 0)
    AS DECIMAL(5,1))                                                        AS priority_ontime_pct,
    -- Revenue
    ISNULL(SUM(CASE WHEN b.payment_status = 'successful' THEN b.amount_paid ELSE 0 END), 0) AS prepay_revenue_30d,
    -- Snapshot date
    CAST(SYSUTCDATETIME() AS DATE)                                          AS snapshot_date
FROM base b
CROSS JOIN reminder_stats rs
CROSS JOIN delay_stats ds;
GO

-- ── V2: Weekly no-show trend (Power BI line chart) ────────────
CREATE OR ALTER VIEW dbo.vw_weekly_noshow AS
SELECT
    d.year                                                                  AS year,
    d.week_number                                                           AS iso_week,
    MIN(d.full_date)                                                        AS week_start,
    MAX(d.full_date)                                                        AS week_end,
    COUNT(a.appointment_id)                                                 AS total_appointments,
    SUM(CASE WHEN a.status = 'no_show'  THEN 1 ELSE 0 END)                 AS no_shows,
    SUM(CASE WHEN a.status = 'attended' THEN 1 ELSE 0 END)                 AS attended,
    SUM(CASE WHEN a.status = 'rescheduled' THEN 1 ELSE 0 END)              AS rescheduled,
    CAST(
        100.0 * SUM(CASE WHEN a.status = 'no_show' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(a.appointment_id), 0)
    AS DECIMAL(5,1))                                                        AS no_show_rate_pct,
    40.0                                                                    AS baseline_pct,
    30.0                                                                    AS target_pct,
    -- Week-over-week change
    CAST(
        100.0 * SUM(CASE WHEN a.status = 'no_show' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(a.appointment_id), 0)
      - LAG(
            100.0 * SUM(CASE WHEN a.status = 'no_show' THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(a.appointment_id), 0)
        ) OVER (ORDER BY d.year, d.week_number)
    AS DECIMAL(5,2))                                                        AS wow_change_pct
FROM dbo.dim_date d
JOIN dbo.appointments a
    ON CAST(a.scheduled_at AS DATE) = d.full_date
WHERE d.full_date >= DATEADD(WEEK, -26, CAST(SYSUTCDATETIME() AS DATE))
GROUP BY d.year, d.week_number;
GO

-- ── V3: Daily Active Users ─────────────────────────────────────
CREATE OR ALTER VIEW dbo.vw_daily_active_users AS
WITH activity AS (
    SELECT CAST(a.scheduled_at AS DATE)  AS activity_date,
           a.customer_id,
           a.salon_id,
           a.appointment_id
    FROM dbo.appointments a
    WHERE a.status IN ('attended','cancelled','rescheduled','no_show')
    UNION
    SELECT CAST(re.sent_at AS DATE),
           a.customer_id,
           a.salon_id,
           a.appointment_id
    FROM dbo.reminder_events re
    JOIN dbo.appointments a ON a.appointment_id = re.appointment_id
    WHERE re.customer_action IS NOT NULL
      AND re.sent_at IS NOT NULL
)
SELECT
    d.full_date                                                             AS activity_date,
    d.day_name,
    d.week_number,
    d.month_name,
    d.year,
    COUNT(DISTINCT ac.customer_id)                                          AS dau,
    COUNT(DISTINCT ac.salon_id)                                             AS active_salons,
    COUNT(DISTINCT ac.appointment_id)                                       AS active_appointments,
    AVG(COUNT(DISTINCT ac.customer_id)) OVER (
        ORDER BY d.full_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    )                                                                       AS dau_7day_avg
FROM dbo.dim_date d
LEFT JOIN activity ac ON ac.activity_date = d.full_date
WHERE d.full_date BETWEEN DATEADD(DAY, -90, CAST(SYSUTCDATETIME() AS DATE))
                      AND CAST(SYSUTCDATETIME() AS DATE)
GROUP BY d.full_date, d.day_name, d.week_number, d.month_name, d.year;
GO

-- ── V4: Conversion funnel (monthly) ───────────────────────────
CREATE OR ALTER VIEW dbo.vw_conversion_funnel AS
WITH monthly AS (
    SELECT
        d.year,
        d.month_number,
        d.month_name,
        DATEFROMPARTS(d.year, d.month_number, 1) AS month_start,
        a.appointment_id,
        a.customer_id,
        a.status
    FROM dbo.appointments a
    JOIN dbo.dim_date d ON CAST(a.scheduled_at AS DATE) = d.full_date
    WHERE a.scheduled_at >= DATEADD(MONTH, -6, CAST(SYSUTCDATETIME() AS DATE))
),
rem AS (
    SELECT
        re.appointment_id,
        MAX(CASE WHEN re.delivery_status = 'sent'          THEN 1 ELSE 0 END) AS was_delivered,
        MAX(CASE WHEN re.customer_action IS NOT NULL        THEN 1 ELSE 0 END) AS was_engaged
    FROM dbo.reminder_events re
    GROUP BY re.appointment_id
)
SELECT
    m.year,
    m.month_number,
    m.month_name,
    m.month_start,
    COUNT(DISTINCT m.appointment_id)                                         AS step1_bookings,
    COUNT(DISTINCT CASE WHEN r.was_delivered = 1 THEN m.appointment_id END)  AS step2_reminder_delivered,
    COUNT(DISTINCT CASE WHEN r.was_engaged   = 1 THEN m.appointment_id END)  AS step3_reminder_engaged,
    COUNT(DISTINCT CASE WHEN m.status IN ('attended','rescheduled')
                         THEN m.appointment_id END)                          AS step4_attended_rescheduled,
    COUNT(DISTINCT CASE WHEN m.status = 'no_show'
                         THEN m.appointment_id END)                          AS step5_no_show,
    -- Conversion rates
    CAST(
        100.0 * COUNT(DISTINCT CASE WHEN r.was_delivered = 1 THEN m.appointment_id END)
              / NULLIF(COUNT(DISTINCT m.appointment_id), 0)
    AS DECIMAL(5,1))                                                         AS pct_delivered,
    CAST(
        100.0 * COUNT(DISTINCT CASE WHEN r.was_engaged = 1 THEN m.appointment_id END)
              / NULLIF(COUNT(DISTINCT m.appointment_id), 0)
    AS DECIMAL(5,1))                                                         AS pct_engaged,
    CAST(
        100.0 * COUNT(DISTINCT CASE WHEN m.status IN ('attended','rescheduled')
                                    THEN m.appointment_id END)
              / NULLIF(COUNT(DISTINCT m.appointment_id), 0)
    AS DECIMAL(5,1))                                                         AS pct_attended,
    CAST(
        100.0 * COUNT(DISTINCT CASE WHEN m.status = 'no_show' THEN m.appointment_id END)
              / NULLIF(COUNT(DISTINCT m.appointment_id), 0)
    AS DECIMAL(5,1))                                                         AS pct_no_show
FROM monthly m
LEFT JOIN rem r ON r.appointment_id = m.appointment_id
GROUP BY m.year, m.month_number, m.month_name, m.month_start;
GO

-- ── V5: Cohort retention ───────────────────────────────────────
CREATE OR ALTER VIEW dbo.vw_cohort_retention AS
WITH first_booking AS (
    SELECT
        customer_id,
        DATEFROMPARTS(YEAR(MIN(created_at)), MONTH(MIN(created_at)), 1) AS cohort_month
    FROM dbo.appointments
    GROUP BY customer_id
),
monthly_activity AS (
    SELECT DISTINCT
        a.customer_id,
        DATEFROMPARTS(YEAR(a.created_at), MONTH(a.created_at), 1)  AS activity_month
    FROM dbo.appointments a
    WHERE a.status IN ('attended','rescheduled')
)
SELECT
    fb.cohort_month,
    FORMAT(fb.cohort_month, 'MMM yyyy')                                      AS cohort_label,
    DATEDIFF(MONTH, fb.cohort_month, ma.activity_month)                      AS months_since_first,
    COUNT(DISTINCT ma.customer_id)                                           AS retained_customers,
    COUNT(DISTINCT fb.customer_id)                                           AS cohort_size,
    CAST(
        100.0 * COUNT(DISTINCT ma.customer_id)
              / NULLIF(COUNT(DISTINCT fb.customer_id), 0)
    AS DECIMAL(5,1))                                                         AS retention_rate_pct
FROM first_booking fb
LEFT JOIN monthly_activity ma
       ON ma.customer_id     = fb.customer_id
      AND ma.activity_month >= fb.cohort_month
WHERE fb.cohort_month >= DATEADD(MONTH, -12, CAST(SYSUTCDATETIME() AS DATE))
GROUP BY fb.cohort_month, ma.activity_month;
GO

-- ── V6: Drop-off signals ───────────────────────────────────────
CREATE OR ALTER VIEW dbo.vw_dropoff_signals AS
SELECT
    drop_off_point,
    occurrences,
    pct_of_step,
    risk_level,
    feature_area,
    fr_reference
FROM (VALUES
    ('No action after reminder',     NULL, NULL, 'High',   'Reminder System',   'FR-1.9 / FR-1.10'),
    ('Reminder delivery failure',    NULL, NULL, 'High',   'Reminder System',   'FR-1.10'),
    ('No action at 60+ min delay',   NULL, NULL, 'High',   'Live Delay Tracker','FR-2.6 / FR-2.8'),
    ('Payment hold expired',         NULL, NULL, 'Medium', 'Pre-Payment',       'FR-3.8'),
    ('Payment failed (Razorpay)',     NULL, NULL, 'Medium', 'Pre-Payment',       'FR-3.5'),
    ('Late booking – reminders skipped', NULL, NULL, 'Low','Reminder System',   'FR-1.6')
) AS t(drop_off_point, occurrences, pct_of_step, risk_level, feature_area, fr_reference);
GO

-- ── V6b: Live drop-off counts (joins to event tables) ─────────
CREATE OR ALTER VIEW dbo.vw_dropoff_counts AS
WITH window30 AS (
    SELECT a.appointment_id, a.status, a.payment_status
    FROM dbo.appointments a
    WHERE a.scheduled_at >= DATEADD(DAY, -30, CAST(SYSUTCDATETIME() AS DATE))
)
SELECT 'No action after reminder'    AS drop_off_point,
       COUNT(*)                      AS occurrences
FROM dbo.reminder_events re
JOIN window30 w ON w.appointment_id = re.appointment_id
WHERE re.delivery_status = 'sent'
  AND re.customer_action IS NULL
UNION ALL
SELECT 'Reminder delivery failure',
       COUNT(*)
FROM dbo.reminder_events re
JOIN window30 w ON w.appointment_id = re.appointment_id
WHERE re.delivery_status = 'failed'
UNION ALL
SELECT 'No action at 60+ min delay',
       COUNT(*)
FROM dbo.delay_events de
JOIN window30 w ON w.appointment_id = de.appointment_id
WHERE de.reschedule_shown = 1
  AND (de.customer_action IS NULL OR de.customer_action = 'none')
UNION ALL
SELECT 'Payment hold expired',
       COUNT(*)
FROM window30
WHERE payment_status = 'expired'
UNION ALL
SELECT 'Payment failed (Razorpay)',
       COUNT(*)
FROM window30
WHERE payment_status = 'failed';
GO

-- ── V7: Reminder engagement by type ───────────────────────────
CREATE OR ALTER VIEW dbo.vw_reminder_by_type AS
SELECT
    re.reminder_type,
    CASE re.reminder_type
        WHEN 'confirmation' THEN 1 WHEN '24h' THEN 2
        WHEN '2h'           THEN 3 WHEN '1h'  THEN 4
        WHEN '30min'        THEN 5 ELSE 9
    END                                                                     AS sort_order,
    COUNT(*)                                                                AS total_sent,
    SUM(CASE WHEN re.delivery_status = 'failed'            THEN 1 ELSE 0 END) AS delivery_failures,
    SUM(CASE WHEN re.delivery_status = 'merged'            THEN 1 ELSE 0 END) AS merged_messages,
    SUM(CASE WHEN re.customer_action = 'reschedule'        THEN 1 ELSE 0 END) AS action_reschedule,
    SUM(CASE WHEN re.customer_action = 'cancel'            THEN 1 ELSE 0 END) AS action_cancel,
    SUM(CASE WHEN re.customer_action IS NOT NULL           THEN 1 ELSE 0 END) AS total_engaged,
    CAST(
        100.0 * SUM(CASE WHEN re.delivery_status = 'failed' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*), 0)
    AS DECIMAL(5,1))                                                        AS failure_rate_pct,
    CAST(
        100.0 * SUM(CASE WHEN re.customer_action IS NOT NULL THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*), 0)
    AS DECIMAL(5,1))                                                        AS engagement_rate_pct,
    60.0                                                                    AS engagement_target_pct
FROM dbo.reminder_events re
JOIN dbo.appointments a ON a.appointment_id = re.appointment_id
WHERE re.sent_at >= DATEADD(DAY, -30, CAST(SYSUTCDATETIME() AS DATE))
GROUP BY re.reminder_type;
GO

-- ── V8: Delay band distribution & outcomes ────────────────────
CREATE OR ALTER VIEW dbo.vw_delay_bands AS
WITH latest_per_appt AS (
    -- Use the worst (highest) delay band per appointment
    SELECT
        de.appointment_id,
        MAX(de.delay_minutes)   AS max_delay_minutes,
        MAX(CASE de.delay_band
            WHEN 'major'    THEN 4
            WHEN 'moderate' THEN 3
            WHEN 'minor'    THEN 2
            ELSE 1 END)         AS worst_band_rank
    FROM dbo.delay_events de
    GROUP BY de.appointment_id
),
banded AS (
    SELECT
        lpa.appointment_id,
        lpa.max_delay_minutes,
        CASE lpa.worst_band_rank
            WHEN 4 THEN 'Major (60+ min)'
            WHEN 3 THEN 'Moderate (30-59 min)'
            WHEN 2 THEN 'Minor (1-29 min)'
            ELSE        'On schedule'
        END                     AS delay_band_label,
        lpa.worst_band_rank     AS band_sort
    FROM latest_per_appt lpa
)
SELECT
    b.delay_band_label,
    b.band_sort,
    COUNT(DISTINCT b.appointment_id)                                         AS total_appointments,
    SUM(CASE WHEN de.reschedule_shown = 1                   THEN 1 ELSE 0 END) AS reschedule_offered,
    SUM(CASE WHEN de.customer_action = 'reschedule'         THEN 1 ELSE 0 END) AS rescheduled,
    SUM(CASE WHEN a.status = 'attended'                     THEN 1 ELSE 0 END) AS ultimately_attended,
    SUM(CASE WHEN a.status = 'no_show'                      THEN 1 ELSE 0 END) AS ultimately_no_show,
    CAST(
        100.0 * SUM(CASE WHEN de.customer_action = 'reschedule' THEN 1 ELSE 0 END)
              / NULLIF(SUM(CASE WHEN de.reschedule_shown = 1 THEN 1 ELSE 0 END), 0)
    AS DECIMAL(5,1))                                                         AS reschedule_take_rate_pct,
    70.0                                                                     AS reschedule_target_pct
FROM banded b
JOIN dbo.delay_events de ON de.appointment_id = b.appointment_id
JOIN dbo.appointments  a  ON a.appointment_id  = b.appointment_id
GROUP BY b.delay_band_label, b.band_sort;
GO

-- ── V9: Pre-payment funnel (weekly) ───────────────────────────
CREATE OR ALTER VIEW dbo.vw_prepay_funnel AS
SELECT
    d.year,
    d.week_number,
    MIN(d.full_date)                                                         AS week_start,
    COUNT(a.appointment_id)                                                  AS eligible_bookings,
    SUM(CASE WHEN a.payment_status != 'not_applicable'      THEN 1 ELSE 0 END) AS chose_prepay,
    SUM(CASE WHEN a.payment_status = 'successful'           THEN 1 ELSE 0 END) AS paid_successfully,
    SUM(CASE WHEN a.payment_status = 'failed'               THEN 1 ELSE 0 END) AS payment_failed,
    SUM(CASE WHEN a.payment_status = 'expired'              THEN 1 ELSE 0 END) AS slot_hold_expired,
    CAST(
        100.0 * SUM(CASE WHEN a.payment_status = 'successful' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(a.appointment_id), 0)
    AS DECIMAL(5,1))                                                         AS adoption_rate_pct,
    55.0                                                                     AS adoption_target_pct,
    ISNULL(AVG(CASE WHEN a.payment_status = 'successful'
                    THEN a.discount_pct END), 0)                             AS avg_discount_pct,
    ISNULL(SUM(CASE WHEN a.payment_status = 'successful'
                    THEN a.amount_paid ELSE 0 END), 0)                       AS prepay_revenue,
    ISNULL(SUM(CASE WHEN a.payment_status = 'successful'
                    THEN a.original_price * a.discount_pct / 100
                    ELSE 0 END), 0)                                          AS discount_value_given
FROM dbo.appointments a
JOIN dbo.dim_date d ON CAST(a.created_at AS DATE) = d.full_date
JOIN dbo.salons   s ON s.salon_id = a.salon_id AND s.prepay_enabled = 1
WHERE d.full_date >= DATEADD(WEEK, -12, CAST(SYSUTCDATETIME() AS DATE))
GROUP BY d.year, d.week_number;
GO

-- ── V10: Priority Service on-time rate ────────────────────────
CREATE OR ALTER VIEW dbo.vw_priority_ontime AS
SELECT
    d.year,
    d.week_number,
    MIN(d.full_date)                                                         AS week_start,
    COUNT(a.appointment_id)                                                  AS priority_appointments,
    SUM(CASE WHEN a.status = 'attended'
              AND DATEDIFF(MINUTE, a.scheduled_at, a.marked_at) <= 5
             THEN 1 ELSE 0 END)                                              AS on_time_count,
    SUM(CASE WHEN a.status = 'attended'
              AND DATEDIFF(MINUTE, a.scheduled_at, a.marked_at) > 5
             THEN 1 ELSE 0 END)                                              AS late_count,
    CAST(
        100.0 * SUM(CASE WHEN a.status = 'attended'
                          AND DATEDIFF(MINUTE, a.scheduled_at, a.marked_at) <= 5
                         THEN 1 ELSE 0 END)
              / NULLIF(COUNT(a.appointment_id), 0)
    AS DECIMAL(5,1))                                                         AS on_time_rate_pct,
    90.0                                                                     AS target_pct
FROM dbo.appointments a
JOIN dbo.dim_date d ON CAST(a.scheduled_at AS DATE) = d.full_date
WHERE a.is_priority = 1
  AND d.full_date >= DATEADD(WEEK, -12, CAST(SYSUTCDATETIME() AS DATE))
GROUP BY d.year, d.week_number;
GO

-- ── V11: Feature adoption per salon ───────────────────────────
CREATE OR ALTER VIEW dbo.vw_feature_adoption AS
SELECT
    s.salon_id,
    s.salon_name,
    s.city,
    s.plan_tier,
    s.onboarded_at,
    s.reminder_30min,
    s.delay_tracker,
    s.prepay_enabled,
    s.prepay_discount,
    -- Feature score 0-3
    (CAST(s.reminder_30min AS INT)
   + CAST(s.delay_tracker  AS INT)
   + CAST(s.prepay_enabled AS INT))                                          AS features_enabled_count,
    -- Activity stats
    COUNT(DISTINCT a.appointment_id)                                         AS total_appointments_30d,
    SUM(CASE WHEN a.status = 'no_show' THEN 1 ELSE 0 END)                   AS no_shows_30d,
    CAST(
        100.0 * SUM(CASE WHEN a.status = 'no_show' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(DISTINCT a.appointment_id), 0)
    AS DECIMAL(5,1))                                                         AS salon_noshow_rate_pct,
    -- Reminder engagement
    CAST(
        100.0 * SUM(CASE WHEN re.customer_action IS NOT NULL THEN 1 ELSE 0 END)
              / NULLIF(COUNT(re.event_id), 0)
    AS DECIMAL(5,1))                                                         AS reminder_engagement_pct,
    -- Pre-pay adoption
    CAST(
        100.0 * SUM(CASE WHEN a.payment_status = 'successful' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(DISTINCT CASE WHEN s.prepay_enabled = 1
                                          THEN a.appointment_id END), 0)
    AS DECIMAL(5,1))                                                         AS prepay_adoption_pct
FROM dbo.salons s
LEFT JOIN dbo.appointments  a  ON a.salon_id         = s.salon_id
                               AND a.scheduled_at   >= DATEADD(DAY, -30, CAST(SYSUTCDATETIME() AS DATE))
LEFT JOIN dbo.reminder_events re ON re.appointment_id = a.appointment_id
WHERE s.is_active = 1
GROUP BY
    s.salon_id, s.salon_name, s.city, s.plan_tier, s.onboarded_at,
    s.reminder_30min, s.delay_tracker, s.prepay_enabled,
    s.prepay_discount;
GO

-- ── V12: Message merge compliance (cross-feature rule CF-1) ───
CREATE OR ALTER VIEW dbo.vw_merge_compliance AS
WITH overlaps AS (
    SELECT
        re.event_id,
        re.appointment_id,
        re.reminder_type,
        re.sent_at,
        re.delivery_status,
        d.full_date,
        d.week_number,
        d.year
    FROM dbo.reminder_events re
    JOIN dbo.delay_events de
        ON de.appointment_id = re.appointment_id
       AND ABS(DATEDIFF(SECOND, re.sent_at, de.triggered_at)) < 120
    JOIN dbo.dim_date d ON CAST(re.sent_at AS DATE) = d.full_date
    WHERE re.reminder_type IN ('2h','1h')
      AND re.sent_at >= DATEADD(WEEK, -4, CAST(SYSUTCDATETIME() AS DATE))
)
SELECT
    o.year,
    o.week_number,
    MIN(d.full_date)                                                         AS week_start,
    COUNT(o.event_id)                                                        AS total_overlaps,
    SUM(CASE WHEN o.delivery_status = 'merged'    THEN 1 ELSE 0 END)        AS correctly_merged,
    SUM(CASE WHEN o.delivery_status != 'merged'   THEN 1 ELSE 0 END)        AS violation_count,
    CAST(
        100.0 * SUM(CASE WHEN o.delivery_status = 'merged' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(o.event_id), 0)
    AS DECIMAL(5,1))                                                         AS compliance_pct
FROM overlaps o
JOIN dbo.dim_date d ON d.year = o.year AND d.week_number = o.week_number
GROUP BY o.year, o.week_number;
GO

-- ================================================================
-- 5. STORED PROCEDURES
-- ================================================================

-- ── SP1: Refresh analytics summary cache (run nightly) ─────────
CREATE OR ALTER PROCEDURE dbo.usp_refresh_analytics_cache
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @log_msg NVARCHAR(500);
    DECLARE @start   DATETIME2 = SYSUTCDATETIME();

    -- Update customer total_bookings
    UPDATE c
    SET    c.total_bookings = sub.booking_count
    FROM   dbo.customers c
    JOIN  (SELECT customer_id, COUNT(*) AS booking_count
           FROM   dbo.appointments
           GROUP BY customer_id) sub ON sub.customer_id = c.customer_id;

    SET @log_msg = CONCAT(
        'Refresh complete. Duration: ',
        DATEDIFF(MILLISECOND, @start, SYSUTCDATETIME()), 'ms. ',
        'Rows updated: ', @@ROWCOUNT
    );
    RAISERROR(@log_msg, 0, 1) WITH NOWAIT;
END;
GO

-- ── SP2: Get Power BI parameter values ─────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_get_dashboard_params
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        CAST(SYSUTCDATETIME() AS DATE)          AS today,
        DATEADD(WEEK, -26, CAST(SYSUTCDATETIME() AS DATE)) AS default_start_26w,
        DATEADD(WEEK, -12, CAST(SYSUTCDATETIME() AS DATE)) AS default_start_12w,
        DATEADD(DAY,  -30, CAST(SYSUTCDATETIME() AS DATE)) AS default_start_30d,
        40.0                                    AS baseline_noshow_pct,
        30.0                                    AS target_noshow_pct,
        60.0                                    AS reminder_engagement_target,
        95.0                                    AS delay_delivery_target,
        70.0                                    AS reschedule_via_delay_target,
        55.0                                    AS prepay_adoption_target,
        90.0                                    AS priority_ontime_target;
END;
GO

-- ================================================================
-- 6. POWER BI DATASET QUERY STUBS
-- (Paste each into Power BI Desktop → Transform Data → New Query)
-- ================================================================

/*
── PBI Query 1: KPI Cards ──────────────────────────────────────
SELECT * FROM dbo.vw_kpi_snapshot;

── PBI Query 2: No-Show Trend Line ─────────────────────────────
SELECT week_start, no_show_rate_pct, target_pct, baseline_pct,
       total_appointments, no_shows, attended
FROM   dbo.vw_weekly_noshow
ORDER  BY week_start;

── PBI Query 3: DAU ─────────────────────────────────────────────
SELECT activity_date, dau, active_salons, dau_7day_avg,
       day_name, week_number
FROM   dbo.vw_daily_active_users
ORDER  BY activity_date;

── PBI Query 4: Conversion Funnel ───────────────────────────────
SELECT month_start, month_name, year,
       step1_bookings, step2_reminder_delivered,
       step3_reminder_engaged, step4_attended_rescheduled, step5_no_show,
       pct_delivered, pct_engaged, pct_attended, pct_no_show
FROM   dbo.vw_conversion_funnel
ORDER  BY month_start;

── PBI Query 5: Retention Cohort ────────────────────────────────
SELECT cohort_label, months_since_first, retained_customers,
       cohort_size, retention_rate_pct
FROM   dbo.vw_cohort_retention
ORDER  BY cohort_label, months_since_first;

── PBI Query 6: Drop-off Counts ────────────────────────────────
SELECT drop_off_point, occurrences
FROM   dbo.vw_dropoff_counts
ORDER  BY occurrences DESC;

── PBI Query 7: Reminder by Type ───────────────────────────────
SELECT reminder_type, sort_order, total_sent,
       delivery_failures, failure_rate_pct,
       total_engaged, engagement_rate_pct, engagement_target_pct
FROM   dbo.vw_reminder_by_type
ORDER  BY sort_order;

── PBI Query 8: Delay Bands ────────────────────────────────────
SELECT delay_band_label, band_sort, total_appointments,
       reschedule_offered, rescheduled, reschedule_take_rate_pct,
       ultimately_attended, ultimately_no_show, reschedule_target_pct
FROM   dbo.vw_delay_bands
ORDER  BY band_sort;

── PBI Query 9: Pre-Payment Funnel ─────────────────────────────
SELECT week_start, eligible_bookings, chose_prepay,
       paid_successfully, payment_failed, slot_hold_expired,
       adoption_rate_pct, adoption_target_pct,
       avg_discount_pct, prepay_revenue, discount_value_given
FROM   dbo.vw_prepay_funnel
ORDER  BY week_start;

── PBI Query 10: Priority On-Time ──────────────────────────────
SELECT week_start, priority_appointments,
       on_time_count, late_count, on_time_rate_pct, target_pct
FROM   dbo.vw_priority_ontime
ORDER  BY week_start;

── PBI Query 11: Feature Adoption per Salon ────────────────────
SELECT salon_name, city, plan_tier, onboarded_at,
       reminder_30min, delay_tracker, prepay_enabled,
       features_enabled_count, salon_noshow_rate_pct,
       reminder_engagement_pct, prepay_adoption_pct
FROM   dbo.vw_feature_adoption
ORDER  BY features_enabled_count DESC, salon_noshow_rate_pct ASC;

── PBI Query 12: Merge Compliance ──────────────────────────────
SELECT week_start, total_overlaps, correctly_merged,
       violation_count, compliance_pct
FROM   dbo.vw_merge_compliance
ORDER  BY week_start;
*/
