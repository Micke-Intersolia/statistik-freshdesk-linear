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

## 11. Ny Power BI-sida — Labels & Prioritet ⬅ NÄSTA SESSION

**Vad:** En ny rapportsida med statistik grupperad på Linear-labels och prioritet.

---

### Stakeholder-beslut (2026-06-25) — klara att bygga på

| Fråga | Beslut |
|---|---|
| Automatiserade labels (OwlMonitor, Routine m.fl.) | **Visa** — de är manuellt arbete (ticket = du måste göra nåt) |
| Gruppering i 6 grupper | **Godkänd** — men drill-down till enskilda labels krävs |
| Issues utan label (58 %) | **Visa som "Ingen label"** — stakeholder förvånad över få labels |
| Routine med Urgent/High | **Korrekt** — Routine = återkommande jobb, ofta quick wins |
| Incidents utan prioritet | **OK** — ingen minimikrav på prioritet för incidents |
| Investigation = nästan alltid hög prio | **Korrekt** — undersökningar prioriteras högt medvetet |
| Medium dominerar (51 %) | Troligen en standard-default, inte medvetet val |
| Urgent 98 % stängda | **Lyft som positivt nyckeltal** |
| Low-prio fastnar | **Naturligt och accepterat** |
| Issues utan prioritet (28 %) | **Visa som "Ingen prioritet"** — stakeholder prioriterar sällan, tar direkt i ordning |

---

### Godkänd label-gruppering

| Grupp | Labels |
|---|---|
| Automatiserat | OwlMonitor, Routine, Auto Reminder Task, Auto Generated Report |
| Bug/Problem | Bug, Recurring Issue, Data Issue, Data restoration |
| Förbättring | Improvement, Feature, Investigation |
| Incident | Incident |
| Produkt-specifikt | Phrases, Lists, Mobil App*, Trafic Lights*, Customer Move, Substitution |
| Process | Risk Assessment, Team effort, Maintenance, Back2Triage |
| Ingen label | Issues där `labels` är blank |

*Stavfel i källdata — normaliseras i Power BI via SWITCH, inte i SQL.

---

### Implementationsplan

**Steg 1 — Bryggtabell i Power Query**
- Referera FactLinear i Power Query
- Dela `labels`-kolumnen på `|`-separator → unpivot → en rad per label per issue
- Resultat: tabell `FactLinear_Labels` med kolumnerna `id` + `label_name`
- Issues utan labels ingår EJ i bryggtabellen — hanteras separat via mått

**Steg 2 — Beräknad kolumn: Label Group**
- Lägg till `Label Group`-kolumn på `FactLinear_Labels` via SWITCH på `label_name`
- Normalisera stavfel: "Mobil App" → "Mobile App", "Trafic Lights" → "Traffic Lights"

**Steg 3 — Hierarki för drill-down**
- Skapa hierarki på FactLinear_Labels: `Label Group` → `label_name`
- Aktivera drill-down på stapeldiagrammet för labels

**Steg 4 — Relationer**
- Många-till-många: `FactLinear[id]` ↔ `FactLinear_Labels[id]`
- "Ingen label"-issues: mått som räknar `ISBLANK(labels)` direkt från FactLinear

**Steg 5 — Sidlayout**

*Övre halvan — Labels:*
- Horisontellt stapeldiagram: antal issues per Label Group (inkl. "Ingen label")
  - Drill-down till enskild label
  - Samma brand-gröna färg (#2C786C) — längden berättar historien
- Måttsläpare: Totalt | Öppet | Stängt (via slicer eller toggle)

*Nedre halvan — Prioritet:*
- KPI-kort: **Urgent closure rate** (positivt nyckeltal — "98 % stängda")
- Stapeldiagram: Issues per prioritet (Urgent → High → Medium → Low → Ingen prioritet)
  - Färgkodning: Urgent=#F04438 (röd), High=#F79009 (amber), Medium=#2C786C (grön), Low=#54B09E, Ingen=#B1E2D5
- Tabell: Prioritet | Totalt | Stängt | Öppet | Öppen andel %

*Header:* Mörk (#101828) med vit logo + Month-slicer (dropdown), konsistent med övriga sidor.

---

### Underlagsdata (query 2026-06-25)

**Täckningsgrad:**

| Kategori | Antal | Andel |
|---|---|---|
| Ingen label | 634 | 58 % |
| Automatiserade labels | ~293 | 27 % |
| Övriga labels | ~156 | 14 % |
| Incident | 9 | 1 % |

**Prioritetsfördelning:**

| Prioritet | Totalt | Stängt | Öppet | Öppen andel |
|---|---|---|---|---|
| No priority | 302 | 293 | 9 | 3 % |
| Urgent | 48 | 47 | 1 | 2 % |
| High | 152 | 137 | 15 | 10 % |
| Medium | 557 | 521 | 36 | 6 % |
| Low | 24 | 20 | 4 | 17 % |

**Överlapp:**

| Antal labels per issue | Antal issues |
|---|---|
| 1 label | 422 |
| 2 labels | 23 |
| 3 labels | 4 |

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
