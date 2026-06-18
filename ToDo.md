# Power BI — To-Do List

---

## ✅ 1. Front page / summary — DONE (2026-06-12)

## ✅ 2a. Add Quarter to the date hierarchy — DONE (2026-06-12)

## ~~2b. Detail pages (drill-enabled bar chart, open issues table)~~ — DROPPED (2026-06-18)
Decided against during redesign — "trim the fat" principle. Trend and Distribution pages cover the need.

## ✅ 3. Assignee daily/weekly flow — DONE (2026-06-18)
Heatmap + backlog trend line folded into Linear - Assignee page. Hero visual changed to Open at Month End per person.

## ✅ 4. Lead time threshold — DONE (2026-06-18, different approach)
Implemented as Lead Time bucket chart with green→red gradient + Backlog Growth and Avg age Open Issues KPI cards.

---

## 8. Tooltip — filter out incomplete current period

**What:** The Tooltip - Assignee Weekly bar chart shows the current (incomplete) week as a small stub, making it look like productivity collapsed.

**Fix (simple):** Add visual-level filter on the tooltip bar chart: `DimDate[Is Current Month] = 0`. Excludes current month entirely — hides partial data at the cost of not showing completed weeks in the current month.

**Fix (precise):** Add a calculated column to DimDate:
```dax
Is Current Week =
IF(
    DimDate[year_week] = FORMAT(TODAY(), "YYYY") & "-W" & FORMAT(WEEKNUM(TODAY(), 2), "00"),
    1, 0
)
```
Then filter on `Is Current Week = 0`. Shows completed weeks in the current month but hides only the current incomplete week.

---

## 9. Freshdesk — replace threshold card with waiting-age table

**What:** Remove the "Tickets waiting longer than X days" card and its 30-day circle input. Replace with a table showing the distribution of how long tickets have been waiting.

**Steps:**
1. Add calculated column to FactFreshdesk:
```dax
Days Waiting =
IF(
    FactFreshdesk[triage_status] = "Waiting",
    DATEDIFF(FactFreshdesk[first_waiting_at], TODAY(), DAY),
    BLANK()
)
```
2. Delete the threshold card and the What-if parameter slicer
3. Add a Table visual: `Days Waiting` + count of `id`
4. Visual-level filters: `triage_status = "Waiting"`, `Days Waiting` is not blank
5. Sort descending by `Days Waiting`
6. Filters on this visual → Top N → Top 10 (or 15)
7. The 6-month page filter applies automatically

---

## 10. Rename "Avg age Open Issues" KPI card title

**What:** The KPI card currently titled "Avg Open Backlog Age" (or similar) should read **"Avg age Open Issues"** — clearer for stakeholders.

**Steps:** Click the card → Format pane → General → Title → change text to "Avg age Open Issues".

---

## 5. Chart-to-KPI drill interaction — DEFERRED

Clicking a month bar should update KPI cards to show that month vs previous. Decided to leave for now — complex rewrite of all `_Helper Measures`, only worth doing if a specific stakeholder need arises.

---

## 6. Remove Freshdesk year filter — CALENDAR ITEM (June 2027)

Once 12+ months of nightly snapshots have accumulated (approx. June 2027), remove the year filter on the Freshdesk page to enable rolling 12-month comparisons. No DAX changes needed.

---

## 7a. Fix `Period Summary` double-prefix — MINOR

The `Period Summary` measure in `_Helper Measures` produces "Period: Period: W23 | Previous: Previous: W22". Not currently used on any page but should be fixed to:
```dax
Period Summary = [Period Label] & "     |     " & [Prev Period Label]
```
Low priority since the measure isn't placed on any page.
