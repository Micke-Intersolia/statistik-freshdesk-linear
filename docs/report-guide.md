# OPEX Statistik — Användarguide för rapporten

En lättläst guide till Power BI-rapporten.
Avsedd för intressenter och nya användare utan tidigare Power BI-erfarenhet.

---

## Vad är den här rapporten?

OPEX Statistik-rapporten visar arbetsbelastning och prestanda för OPEX-teamet på Intersolia. Data hämtas från två system:

- **Linear** — där OPEX hanterar produktärenden, buggar och uppgifter
- **Freshdesk** — där OPEX hanterar kundsupportärenden

Rapporten uppdateras automatiskt varje vardag på morgonen. Det du ser speglar alltid dataläget per igår.

---

## Navigering

Rapporten består av **sju sidor** som visas som flikar längst ned, plus två dolda tooltipsidor. Klicka på en flik för att byta sida. Varje sida fokuserar på en specifik fråga.

| Flik | Innehåll |
|---|---|
| **Summary** | Sammanfattning — viktigaste KPI:erna från alla källor |
| **Freshdesk** | Kundärenden och triagestatus |
| **Linear - Overview** | Övergripande bild av OPEX-ärendena |
| **Linear - Trends** | Trender och ledtider över tid |
| **Linear - Distribution** | Fördelning per projekt och ledtidsbuckets |
| **Linear - Assignee** | Arbetsbelastning per person |
| **Linear - Assignee (details)** | Detaljvy per person med värmekarta |

Börja med **Summary** för den snabbaste överblicken, eller gå direkt till **Linear - Overview** för full periodjämförelse.

---

## Utsnitt — så fungerar filter

Ett **utsnitt** (slicer) är en uppsättning klickbara knappar eller en rullgardinsmeny som filtrerar vad som visas på sidan. När du klickar på ett värde uppdateras alla kopplade diagram.

- **Klicka en gång** för att välja ett värde
- **Ctrl+klicka** för att välja flera värden
- **Klicka på ett redan valt värde** för att avmarkera det
- Knappen **Markera alla** (där den finns) återställer till att visa allt

Alla utsnitt på en sida påverkar inte alltid alla diagram — vissa diagram är avsiktligt frånkopplade för att alltid visa den fullständiga bilden som referens.

---

## Summary

**Frågan den här sidan besvarar:** Hur ser OPEX-teamets totala arbetsbelastning ut just nu — det viktigaste på ett enda ställe?

Den här sidan är startpunkten för presentationer och snabba överblickar. Den innehåller inga detaljer — för djupare analys, gå vidare till respektive detaljsida.

### Utsnitt
- **Vecka / Månad** — samma periodslogik som övriga sidor

### KPI-kort — Linear
| Kort | Vad det betyder |
|---|---|
| **Skapade ärenden** | Nya Linear-ärenden som kom in under perioden |
| **Stängda ärenden** | Linear-ärenden som löstes under perioden |
| **Öppna ärenden** | Nuvarande backlog — ärenden som väntar på lösning |
| **Incidenter** | Brådskande, oplanerade ärenden under perioden |
| **Äldsta ärendet** | Antal dagar som det enskilt äldsta öppna ärendet har väntat (visas i rött) |

### KPI-kort — Freshdesk
| Kort | Vad det betyder |
|---|---|
| **Väntar på triage** | Kundärenden som väntar på bedömning |
| **Passerat triage** | Kundärenden som tagits vidare efter bedömning |
| **Eskaleringsgrad** | Andel kundärenden som eskalerades till OPEX |

### Diagram
Samma stapel- och linjediagram som på Linear - Overview: skapade och stängda ärenden (staplar) och öppen backlog (linje) de senaste fyra månaderna. En stigande linje är det tydligaste tecknet på ett team under press.

---

## Freshdesk

**Frågan den här sidan besvarar:** Hur hanteras kundärenden och hur effektivt fungerar triageprocessen?

### Utsnitt
- **Vecka / Månad** — samma periodslogik som på Linear - Overview

### KPI-kort
| Kort | Vad det betyder |
|---|---|
| **Skapade ärenden** | Nya kundärenden som kom in under perioden |
| **Väntar på triage** | Ärenden som väntar på att bli bedömda |
| **Passerat triage** | Ärenden som har bedömts och tagits vidare |
| **Eskaleringsgrad** | Andel ärenden som eskalerades till OPEX-teamet |
| **Nekad triage** | Ärenden som avvisades vid triage |

### Tröskelkort
"Ärenden som väntat längre än X dagar" — standardgränsen är 30 dagar. Visar hur många ärenden som fastnat i kön längre än förväntat.

### Diagram
Skapade ärenden och eskaleringsgrad per månad — visar om trycket på OPEX ökar.

---

## Linear - Overview

**Frågan den här sidan besvarar:** Hur ser OPEX arbetsbelastning ut just nu jämfört med förra veckan (eller förra månaden)?

### Utsnitt
- **Vecka / Månad** (uppe till vänster) — växlar mellan "senaste hela veckan jämfört med veckan dessförinnan" och "senaste hela månaden jämfört med månaden dessförinnan". Påverkar alla KPI-kort.

### KPI-kort
Varje kort visar ett värde för den aktuella perioden samt en liten pil/procentsats som visar förändringen jämfört med föregående period.

| Kort | Vad det betyder |
|---|---|
| **Skapade ärenden** | Nya ärenden som kom in under perioden — inkommande arbetsbelastning |
| **Stängda ärenden** | Ärenden som löstes under perioden — utfört arbete |
| **Öppna ärenden** | Ärenden som fortfarande är öppna vid periodens slut — backloggen |
| **Incidenter** | Ärenden märkta som incidenter — oplanerat och brådskande arbete |
| **Äldsta ärendet** | Antal dagar som det enskilt äldsta öppna ärendet har väntat |

**Vad man ska titta efter:** Om Skapade konsekvent är fler än Stängda växer backloggen. Öppna ärenden-trenden i diagrammet nedan gör detta synligt över tid.

### Periodsetiketter
Två små kort (t.ex. "Period: V23" och "Föregående: V22") visar exakt vilka datum som jämförs i KPI-korten.

### Diagram
Stapel- och linjediagrammet visar de senaste fyra månaderna:
- **Staplar:** Skapade (vänster stapel) och Stängda (höger stapel) per månad — hur mycket arbete som kom in respektive löstes
- **Linje:** Öppen backlog vid slutet av varje månad — växer eller krymper kön?

En stigande linje är det tydligaste tecknet på ett team under press.

---

## Linear - Trends

**Frågan den här sidan besvarar:** Tar det längre tid att stänga ärenden nu än tidigare, och hinner vi med dem i tillräcklig takt?

### Utsnitt
- **Månadsväljare** — filtrera till specifika månader. Alla KPI-kort reagerar på valet. De två linjediagrammen är avsiktligt frånkopplade och visar alltid den fullständiga trenden.

### KPI-kort
- **Dagar till stängning (medelvärde/median)** — hur lång tid det tar från att ett ärende skapas till att det löses, för ärenden stängda under den valda perioden. Median är mer tillförlitlig än medelvärde när det finns ett fåtal mycket gamla ärenden.

### Diagram
- **Skapade vs Stängda, 3-månaders glidande medelvärde** — utjämnade trendlinjer som visar volymutvecklingen över tid. En bestående lucka mellan linjerna innebär att backloggen växer.
- **Ledtidsuppdelning** — hur lång tid ärenden tillbringar i olika livscykelfaser (Skapat→Startat, Startat→Stängt). Användbart för att hitta var ärenden fastnar.

### Kortet "Äldsta öppna ärende"
Visar alltid det aktuella äldsta olösta ärendet oavsett utsnittval — inklusive ärendets beteckning och titel. Detta är ett medvetet val: det äldsta ärendet är alltid relevant.

---

## Linear - Distribution

**Frågan den här sidan besvarar:** Vilka projekt och ärendetyper tar längst tid att lösa?

### Utsnitt
- **Månadsväljare** — kopplar till båda diagrammen och tabellen.

### KPI-kort
- Samma medelvärde/median för dagar till stängning som på Linear - Trends, nu filtrerat efter ditt månadsval.

### Diagram
- **Ärenden per projektgrupp** (vänster, horisontella staplar) — volym per produktområde under den valda perioden
- **Ledtidsbuckets** (höger, horisontella staplar) — hur ärenden fördelas efter hur lång tid de tog att stänga: Samma dag, 2–7 dagar, 8–14 dagar, 15–30 dagar, 31–90 dagar, +90 dagar. En tung "+90 dagar"-stapel innebär att många ärenden tar mycket lång tid.

### Tabell
Projektgrupp | Medel dagar till stängning | Median dagar till stängning — sorterad med högst medelvärde överst. Visar vilka produktområden som har de långsammaste lösningstiderna.

---

## Linear - Assignee

**Frågan den här sidan besvarar:** Vem gör vad, och hur är arbetsbelastningen fördelad i teamet?

### Utsnitt
- **Månadsväljare** (knappraden längst upp) — filtrerar tabellen och stapeldiagrammet. Linjediagrammet är alltid frånkopplat så att du alltid ser den fullständiga trenden.

### Linjediagram
Skapade ärenden per person och månad — visar varje teammedlems aktivitet över hela perioden. Diagrammet visar alla månader oavsett månadsväljaren, för att alltid ge full trendinformation. Vill du lyfta fram en specifik person, **Ctrl+klicka på deras namn** i diagrammets förklaring.

### Tabell
Tilldelad | Skapade | Stängda | Öppna | Medel dagar till stängning | Incidenter — filtreras av månadsväljaren.

- **Öppna** = personens totala aktuella öppna backlog (det här värdet är alltid aktuellt, inte filtrerat av perioden)
- Fler Skapade än Stängda = personens backlog växer under den valda perioden

### Stapeldiagram
Skapade + Stängda sida vid sida per person, sorterat efter Skapade. En snabb överblick av teamets bidrag och balans.

---

## Linear - Assignee (details)

**Frågan den här sidan besvarar:** Hur utvecklas en specifik persons arbetsbelastning över tid, och när var de som mest belastade?

### Utsnitt
- **Personväljare** — välj en eller flera personer. Alla diagram på sidan uppdateras. Välj en enda person för den tydligaste bilden.

### KPI-kort
- **Öppna** — aktuell öppen backlog för den valda personen
- **Medel dagar till stängning** — hur lång tid den valda personen i genomsnitt tar på sig att lösa ärenden, inom det aktuella 3-månaderfönstret

### Värmekarta (matrix)
Rader = personer, kolumner = månader, cellfärg = arbetsintensitet.
- **Blå celler** = Skapade ärenden den månaden. Mörkare blå = fler skapade ärenden.
- **Gröna celler** = Stängda ärenden den månaden. Mörkare grön = fler stängda ärenden.
- En cell som är mörkblå men ljusgrön innebär att personen skapade mycket men stängde lite — backlog byggs upp.
- En cell där Stängda överstiger Skapade innebär att personen löste äldre ärenden från backloggen den månaden.

**Tips:** Håll muspekaren över en cell för att se ett **popup-diagram** för den personen — ett litet diagram visar Created och Closed per månad för att ge kontext till den valda cellen.

### Trendlinjediagram
Öppen backlog per person under de senaste 3 månaderna. En stigande linje för en person innebär att deras backlog växer — de tar på sig mer arbete än de hinner stänga.

---

## Tips för att använda rapporten

**Hovra:** Håll muspekaren över en stapel, linje eller datapunkt för att se exakta värden i en tooltip.

**Klicka för att filtrera:** På de flesta sidor filtrerar ett klick på en stapel eller ett förklaringsobjekt övriga diagram på sidan. Klicka på samma objekt igen (eller på ett tomt område) för att avmarkera.

**Återställa:** Om sidan verkar filtrerad och du inte vet varför — kontrollera alla utsnitt och klicka på "Markera alla" eller rensa aktiva val.

**Datan är från igår:** Pipelinen körs varje vardag på morgonen. Är det måndag är den senaste datan från fredag.

**Den här versionen av filen:** Power BI-filen är interaktiv, men data är från senaste snapshot 2026-06-12.

**Linear-data finns bara i meningsfull volym från tidigt 2026** — detta speglar när OPEX-teamet tog Linear i bruk, inte ett gap i pipelinen.

---

## Ordlista

| Begrepp | Betydelse |
|---|---|
| **Skapat** | Ett ärende som loggades/öppnades under perioden |
| **Stängt** | Ett ärende som löstes eller avbröts under perioden, oavsett när det skapades |
| **Öppet / Backlog** | Ärenden som finns men ännu inte har lösts |
| **Ledtid** | Totalt antal dagar från att ett ärende skapas till att det löses |
| **Incident** | Ett ärende märkt som incident — typiskt brådskande, oplanerat arbete |
| **Period** | Det tidsfönster som visas i KPI-korten — antingen senaste hela veckan eller senaste hela månaden |
| **3M glidande medelvärde** | Utjämnad trendlinje baserad på ett 3-månadersfönster — minskar veckovisa variationer |
| **Utsnitt** | Filterkontroll i Power BI — knappar eller rullgardinsmeny som styr vad som visas |
