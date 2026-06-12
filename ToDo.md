# Power BI — To-Do List

---

## ✅ 1. Front page / summary — DONE (2026-06-12)

**Purpose:** Stakeholder landing page. No Freshdesk or Linear logo. Shows the most important facts at a glance before the reader navigates to a detail page.

**Suggested layout:**

Top strip: Period toggle (Week / Month slicer) + Period label cards, same as other pages.

Four KPI columns side by side — one per theme:

| Column | Cards |
|---|---|
| **Linear volume** | Created Issues, Closed Issues, Open Issues (with Δ) |
| **Linear health** | Oldest Open Issue (all time), Incidents, Avg Days to Close |
| **Linear people** | Top assignee by open issues (card or small table: Assignee / Open) |
| **Freshdesk** | Waiting for triage, Passed triage, Denied triage (with Δ) — once Freshdesk focus returns |

Below KPIs: one chart per source, kept simple.
- **Linear:** the existing bar+line chart (Created / Closed / Open backlog), last 4 months, no secondary axis label clutter
- **Freshdesk:** a simple bar chart of tickets entering triage per month (once Freshdesk focus returns)

**Power BI steps:**
1. Duplicate an existing page, rename to "Summary" or "Overview"
2. Remove Freshdesk/Linear logos — replace header with plain "OPEX Statistics" text or the Intersolia logo only
3. Resize/rearrange existing card visuals; reuse all existing measures — no new DAX needed
4. Edit Interactions: disable cross-filtering between the two charts

---

## 2. Detail pages — drilldown

**Purpose:** Finer granularity for OPEX to show volume of work and who is doing what. Drilldown: Quarter → Month → Week → Day.

### ✅ 2a. Add Quarter to the date hierarchy — DONE (2026-06-12)

DimDate does not have a quarter column. Add two calculated columns in Power BI on the DimDate table:

```dax
Quarter Label = "Q" & CEILING(DimDate[month] / 3, 1) & " '" & RIGHT(FORMAT(DimDate[year], "0000"), 2)
```
```dax
Quarter Sort = DimDate[year] * 10 + CEILING(DimDate[month] / 3, 1)
```

Sort `Quarter Label` by `Quarter Sort`.

Then in the Fields pane, right-click DimDate → New hierarchy. Add levels in order:
1. Quarter Label (sorted by Quarter Sort)
2. Month Label (sorted by month_sort — already set up)
3. year_week
4. date_key

### 2b. What to show — suggested detail page content for OPEX

OPEX wants to demonstrate workload and show individual contribution. Useful visuals:

**Volume over time (drill-enabled bar chart)**
- X axis: the date hierarchy above — drill from quarter down to day
- Y axis: Created (bars) + Closed (bars) + Open backlog (line, secondary axis)
- Slicer: Assignee (multi-select), Project Group (multi-select)
- This single chart answers "how much work is there and is the backlog growing?"

**Backlog age breakdown (stacked bar or table)**
- Rows: Project Group (or Assignee)
- Columns: Lead Time buckets (Same day / Up to 1 week / etc.)
- Shows where slow issues accumulate and in whose hands

**Priority breakdown over time**
- Stacked bar: Urgent / High / Medium / Low created per month
- Useful for showing whether the team is firefighting (many Urgent) or planning (many Medium/Low)

**Open issues snapshot table**
- Table: Identifier | Title | Assignee | Project Group | Created | Age (days) | Priority
- Sorted by Age descending
- Filtered to open issues only (ISBLANK(closed_at))
- This is the "list of everything still waiting" view — the most concrete evidence of workload

**Power BI steps:**
1. New page, tab name "Detail" (or split into "Detail — Volume" and "Detail — Issues")
2. Add the hierarchy bar chart first — this is the centrepiece
3. Enable drill-down arrows on the visual (the forked-arrow icon in the visual header)
4. Add the open issues table — use FactLinear directly, filter by `ISBLANK(closed_at)` at visual level
5. Add Assignee and Project Group slicers

---

## 3. Assignee daily/weekly flow

**Purpose:** Deeper version of the People page. Shows how work moves per person at weekly (or daily) resolution — useful for spotting who is overloaded, who is clearing backlog, and whether work is evenly distributed.

**Suggested visuals:**

**Weekly created vs closed per assignee (matrix)**
- Rows: Assignee
- Columns: year_week (from DimDate)
- Values: Created (background colour scale: low=white, high=blue), Closed (background colour scale)
- Gives an instant heat-map of who worked when and how much

**Cumulative open issues per assignee over time (line chart)**
- X: Month Label (or year_week for weekly resolution)
- Y: Open Issues Assignee (already exists in `_L Measures 2`, REMOVEFILTERS(DimDate), ISBLANK)
- Legend: Assignee
- Shows whether each person's backlog is growing or shrinking

**Daily flow line chart (optional, noisy)**
- Same as the cumulative chart above but with date_key on X axis
- Only useful if the team logs work daily; weekly is usually cleaner

**Power BI steps:**
1. New page, tab name "People — Detail"
2. Matrix visual: drag Assignee to Rows, year_week to Columns, `_L Measures 3[Created]` and `_L Measures 3[Closed]` to Values
3. Format → Cell elements → Background colour → Gradient for each value column
4. Add the cumulative line chart using the existing `Open Issues Assignee` measure
5. Connect the month slicer from the People page (copy it across)

---

## 4. Lead time threshold — % of issues exceeding X days

The "same-period throughput" metric (created and closed in same period) is just a subset of the closed count — not independently interesting enough for its own card. Drop it.

**Replace with: % of closed issues exceeding a threshold (like Freshdesk's Wait Threshold)**

**What-if parameter:**
- Name: `Close Threshold`
- Range: 1–180, increment 1, default 30
- Power BI auto-generates `[Close Threshold Value]`

**New measure** (add to `_L Measures 2`):
```dax
% Closed Over Threshold =
DIVIDE(
    CALCULATE(
        COUNTROWS(FactLinear),
        NOT ISBLANK(FactLinear[closed_at]),
        FactLinear[days_to_close] > [Close Threshold Value]
    ),
    CALCULATE(
        COUNTROWS(FactLinear),
        NOT ISBLANK(FactLinear[closed_at])
    )
)
```
Format as percentage.

**Suggested placement:** Distribution page (page 3), alongside the Lead Time bucket chart. Put the Close Threshold slicer next to it. Shows "X% of issues took longer than 30 days to close" and lets the reader adjust the threshold interactively.

Can also be broken down by Project Group or Assignee in a table.

---

## 5. Chart-to-KPI drill interaction

**What it should do:** Clicking a month bar in the page 1 chart changes the KPI cards to show that month vs the previous month, instead of the rolling current/previous period.

**Why it is disabled:** The period measures (`[Period Start]`, `[Period End]` etc.) use `TODAY()` to compute a rolling window. When DimDate is cross-filtered by the chart, these measures still return the rolling window — not the clicked month.

**The fix — detect whether a month has been selected:**

Rewrite the helper measures to check `ISFILTERED(DimDate)` (or `SELECTEDVALUE(DimDate[Month Label])`) and switch between rolling logic and selected-month logic:

```dax
_Period End =
IF(
    ISFILTERED(DimDate[month_sort]),
    -- A month bar was clicked: use end of the selected month
    EOMONTH(MIN(DimDate[date_key]), 0),
    -- Normal rolling mode: use today's period
    IF([Selected Period] = "Week", ..., EOMONTH(TODAY(), 0))
)
```

```dax
_Prev Period End =
IF(
    ISFILTERED(DimDate[month_sort]),
    -- End of the month before the selected one
    EOMONTH(MIN(DimDate[date_key]), -1),
    -- Normal rolling mode
    IF([Selected Period] = "Week", ..., EOMONTH(TODAY(), -1))
)
```

`_Period Start` and `_Prev Period Start` follow the same pattern.

**Power BI steps:**
1. Rewrite the four `_Period Start/End` helper measures as above
2. In Edit Interactions: re-enable cross-filtering from the chart to the KPI cards
3. Test: click a month bar → KPI cards should update to that month vs previous month
4. Click blank area to deselect → KPI cards return to rolling period

**Note:** This is the most complex change on this list. Do it last, after all other pages are stable — it touches shared measures used on every page.

---

## 6. Remove Freshdesk year filter

**When:** Once 12+ months of nightly snapshots have accumulated — approximately June 2027 (snapshots started June 2026).

**What to do:**
1. Open Power BI Desktop
2. Go to the Freshdesk page
3. In the Filters pane, remove the visual-level or page-level filter on `DimDate[year]` (or `FactFreshdesk[created_at]`) that restricts to the current year
4. Verify the rolling 12-month view looks correct
5. Check that all Freshdesk KPI cards show sensible Δ values (first full year of comparisons)

No DAX changes needed — the existing measures already handle rolling periods correctly.

---

## 7. Model cleanup — discrepancies found in export (2026-06-11)

These were found by comparing the Power BI model export (CSV files in `Visuals/export/`) against CLAUDE.md and the session history. CLAUDE.md has already been corrected for documentation errors; the items below require changes inside Power BI Desktop.

### 7a. Fix `Period Summary` double-prefix

The `Period Summary` measure in `_Helper Measures` currently reads:
```dax
"Period: " & [Period Label] & " | Previous: " & [Prev Period Label]
```
But `[Period Label]` already returns "Period: W23" and `[Prev Period Label]` already returns "Previous: W22", so the result is "Period: Period: W23 | Previous: Previous: W22".

**Fix:** Update the measure to:
```dax
Period Summary =
[Period Label] & "     |     " & [Prev Period Label]
```
(The measure is currently not placed on any page — you said you want Period Label and Prev Period Label as separate cards. Leave Period Summary as a backup but fix the formula anyway so it doesn't produce nonsense if used later.)

### ✅ 7d. `Open` measure naming — DONE (visual title set directly on the visual, no measure rename needed)

### ✅ 7e. `Lead Time Sort` — DONE (verified 2026-06-12)

The Lead Time bucket labels in the model are:
- Same day (Sort=1), 2–7 days (2), 8–14 days (3), 15–30 days (4), 31–90 days (5), +90 days (6)

The conditional formatting rules on the Lead Time chart (page 3) are keyed to `Lead Time Sort` numeric values (1–6), not the text labels. These should still be correct, but verify the legend labels on the chart show the new names (not the old "Up to one week" etc.). If the chart was built before the labels were changed, a refresh of the visual may be needed.

**No DAX changes needed** — `Lead Time` and `Lead Time Sort` calculated columns in the model already use the correct labels and numbers.
