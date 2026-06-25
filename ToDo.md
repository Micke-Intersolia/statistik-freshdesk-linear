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

## 11. Ny Power BI-sida — Labels & Prioritet

**Vad:** En ny rapportsida med statistik grupperad på Linear-labels och prioritet.

**Underlag — alla labels i nuläget (query 2026-06-25):**

| Label | Totalt | Stängt | Öppet |
|---|---|---|---|
| OwlMonitor | 162 | 160 | 2 |
| Routine | 100 | 98 | 2 |
| Bug | 77 | 62 | 15 |
| Auto Reminder Task | 25 | 24 | 1 |
| Improvement | 23 | 11 | 12 |
| Investigation | 19 | 11 | 8 |
| Phrases | 13 | 6 | 7 |
| Lists | 10 | 9 | 1 |
| Incident | 9 | 7 | 2 |
| Recurring Issue | 9 | 9 | 0 |
| Data restoration | 7 | 4 | 3 |
| Auto Generated Report | 6 | 6 | 0 |
| Customer Move | 4 | 3 | 1 |
| Risk Assessment | 3 | 3 | 0 |
| Mobil App | 3 | 1 | 2 |
| Back2Triage | 3 | 3 | 0 |
| Trafic Lights | 2 | 2 | 0 |
| Feature | 1 | 1 | 0 |
| Team effort | 1 | 1 | 0 |
| Substitution | 1 | 0 | 1 |
| Data Issue | 1 | 0 | 1 |
| Maintenance | 1 | 1 | 0 |

**Föreslagna grupper:**

| Grupp | Labels |
|---|---|
| Automatiserat | OwlMonitor, Routine, Auto Reminder Task, Auto Generated Report |
| Bug/Problem | Bug, Recurring Issue, Data Issue, Data restoration |
| Förbättring | Improvement, Feature, Investigation |
| Incident | Incident |
| Produkt-specifikt | Phrases, Lists, Mobil App, Trafic Lights, Customer Move, Substitution |
| Process | Risk Assessment, Team effort, Maintenance, Back2Triage |

**Överlapp mellan labels (query 2026-06-25):**

| Antal labels per issue | Antal issues |
|---|---|
| 1 label | 422 |
| 2 labels | 23 |
| 3 labels | 4 |

Överlapp är litet (27 issues med flera labels) — en issue kan alltså dyka upp i flera labelgrupper. Hanteras enklast i Power BI via en bryggtabell (många-till-många), inte via en beräknad kolumn.

**Label × Prioritet (query 2026-06-25):**

| Label | No priority | Urgent | High | Medium | Low |
|---|---|---|---|---|---|
| OwlMonitor | 160 | — | 1 | 1 | — |
| Routine | 9 | 5 | 8 | 77 | 1 |
| Auto Reminder Task | 24 | — | — | 1 | — |
| Auto Generated Report | 6 | — | — | — | — |
| Bug | 1 | 6 | 18 | 45 | 7 |
| Improvement | 7 | — | 8 | 7 | 1 |
| Investigation | — | 4 | 8 | 5 | 2 |
| Incident | 2 | 2 | 3 | 2 | — |
| Recurring Issue | — | 2 | 1 | 6 | — |
| Data restoration | — | 1 | 2 | 4 | — |
| Phrases | — | — | 3 | 10 | — |
| Lists | — | — | 2 | 7 | 1 |
| Customer Move | — | — | — | 4 | — |
| Mobil App | — | — | 2 | — | 1 |
| Back2Triage | — | — | — | 3 | — |
| Risk Assessment | — | — | 1 | 2 | — |
| Trafic Lights | — | — | — | 2 | — |
| Maintenance | 1 | — | — | — | — |
| Substitution | — | — | — | 1 | — |
| Team effort | — | — | 1 | — | — |
| Feature | — | — | 1 | — | — |
| Data Issue | — | — | — | 1 | — |

Noteringar:
- **Automatiserade labels driver "No priority"-siffran:** OwlMonitor (160) + Auto Reminder Task (24) + Auto Generated Report (6) = 190 av totalt 302 "No priority"-issues. Om automatiserade filtreras bort sjunker "No priority" från 302 → ~112, vilket är mer meningsfullt att visa
- **Routine har Urgent/High:** 5 Urgent + 8 High trots att det är en "Routine"-label — värt att fråga stakeholder om dessa är manuellt skapade eller om något är fel i labelanvändningen
- **Investigation är nästan alltid hög prio:** 4 Urgent + 8 High av 19 totalt (63 %) — rimligt, undersökningar triggas av problem
- **Incident saknar konsekvent prioritering:** 2 st har "No priority" — borde alla incidents vara Urgent eller High?
- **Bug-fördelningen ser sund ut:** Tyngdpunkt på Medium (58 %) med en rimlig svans av Urgent/High

**Notering:** Två stavfel i källdatan — "Mobil App" och "Trafic Lights" — normaliseras i Power BI via SWITCH, inte i SQL.

**Täckningsgrad (query 2026-06-25):**

| Kategori | Antal | Andel |
|---|---|---|
| Ingen label | 634 | 58 % |
| Automatiserade labels (OwlMonitor / Routine / Auto) | ~293 | 27 % |
| Övriga labels (Bug, Improvement m.fl.) | ~156 | 14 % |
| Incident | 9 | 1 % |

58 % av alla issues saknar label — "Ingen label" måste vara en synlig kategori på sidan, annars ser statistiken missvisande ut.

**Prioritetsfördelning (query 2026-06-25):**

| Prioritet | Totalt | Stängt | Öppet | Öppen andel |
|---|---|---|---|---|
| No priority | 302 | 293 | 9 | 3 % |
| Urgent | 48 | 47 | 1 | 2 % |
| High | 152 | 137 | 15 | 10 % |
| Medium | 557 | 521 | 36 | 6 % |
| Low | 24 | 20 | 4 | 17 % |

Noteringar:
- Medium dominerar (51 % av alla issues) — förväntat men värt att lyfta för stakeholder
- Urgent hanteras snabbast — 98 % stängda, bara 1 öppen
- Low har högst öppen andel (17 %) — låg-prio issues tenderar att fastna i backlog
- No priority är 28 % av alla issues — samma frågeställning som "Ingen label": ska synas men med tydlig etikett

**❓ Beslut krävs från stakeholder:**
Automatiserade labels (OwlMonitor + Routine + Auto Reminder Task + Auto Generated Report) utgör **293 av alla labeled issues** — nästan hälften. De representerar systemgenererade uppgifter, inte mänskligt arbete.

Alternativ:
- **A) Filtrera bort** dem helt från sidan — renare bild av faktiskt arbete
- **B) Visa separat** i en egen grupp "Automatiserat" — ger helhetsbild men kräver tydlig förklaring
- **C) Toggle-slicer** som låter användaren växla — flexibelt men mer komplext

Svaret påverkar om en Label Group-kolumn behöver en hårdkodad exkludering eller inte.

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
