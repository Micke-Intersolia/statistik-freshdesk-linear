# OPEX Statistics

---

## Opening 

- Via API har jag fått fram **Linear**- och **Freshdesk**-data
- Syftet är enligt Henrik att visa hur Opex har (för) mycket att göra. Det bör synas ganska tydligt här. 
- Databasen uppdateras varje morgon

---

## Sid 1 — Summary

- **Diagrammet visar läget** Linjen open backlog är alla Issues som inte är stängda. Ett "hack i kurvan" när Niklas berättade att ni gjord en kämpainsata räcker inte för att motverka trenden med allt fler öppna Issues (just nu 63 stycken, nio fler än förra månaden).
- Äldsta öppna Issue är **220 dagar** gammal. Se tooltip.
- Här finns även lite Freshdesk-data. 
- Se **Month**/**Week** för att jämföra perioderna. .

---

## Sid 2 — Linear - Assignee

*Vem gör jobbet.*

- Backlog för de olika medlemmarna i teamet - **unassigned** är naturligt nog störst, men de flesta har en del öppna Issues liggande.
- Tabellen visar mer detaljer med skapade och stängda Issues per vecka.
- Matrisen (heatmap) har gradients för att man snabbt ska se detaljerna - rött är skapade Issues, grönt är stängda Issues.
- Tooltips för ännu fler detaljer.

---

## Sid 3 — Linear - Overview

- Svarar på frågan: **"Hur gick det förra veckan/månaden jämfört med föregående vecka/månad?"** 
- Vill du se mer info om **Oldest Open Issue** finns en tooltip för det.

---

## Sid 4 — Linear - Trends

- **Rolling averages** visar trenden.
- De två linjerna visar tydligt hur det går, backlog växer generellt, det är inte bara en enstaka händelse. Dock var förra veckan en boost - kanske för att jag skojade till det med John och Niklas, "Det är ingen tävling, men Niklas leder" varpå båda kanske blev lite sugna på att stöka undan Issues ... :) Kanske skulle ha en "leaderboard" anslagen nånstans - eller ett mail med diagram/tabell över vem som gjort flest ärenden i veckan/månaden. 
- Ledtiden **"Created → Started"** visar hur länge Issues blir liggande innan någon tar dem. **"Started → Closed"** visar hur länge de arbetas på. "Created → Started" visar hur Issues hamnar i kö, om "Started → Closed" går upp tar Issues längre tid.
- Genomsnitt och median talar sitt tydliga språk - många Issues stängs ganska omgående, men en del kräver mer arbete.
- Här skulle man kunna utöka med t.ex. prio för att filtrera bort enkla ärenden eller se mer i detalj på de viktigaste Issues. 

---

## Sid 5 — Linear - Distribution

- **Project group** visar vilka produkter som är störst i dataunderlaget. Uncategorized är en hög siffra, beror det på slarv eller något annat?
- **Lead time buckets** visar fördelningen mellan olika Issues och hur lång tid det tar för dem att stängas.
- Tabellen visar snitt/median för de olika produkterna.

---

## Sid 6 — Freshdesk

- Freshdesk-delen är med, men verkar inte vara så intressant i sammanhanget. Den beskriver lite hur många supportärenden som registreras och sedan hur många av dessa som blir aktuella för Opex. 
- I tabellen finns de Tickets som väntat längst under den senaste rullande sexmånadersperioden. Stämmer dessa siffror? Ser märkligt ut, men jag har jobbat efter de status jag fick av Carro.
- Diagrammets intressanta del här är väl escalation rate - om de eskalerar många ärenden till Opex får ni mer jobb och frågan är om alla de ska eskaleras eller om ni ska vara hårdare i triage?

---

## Avslutning

- Vad kan det tänkas finnas här som du vill ha mer av? Mindre av? Något som saknas helt? 
- Jag har tänkt be om något mer att sätta tänderna i - och det behöver inte nödvändigtvis vara databas och Power BI, jag kan gärna bistå om ni ska migrera data till Ester, eller verifiera migrerade data - eller något helt annat. 
- Hur "hemliga" är siffrorna? Internt och externt? Internt vet jag ju redan att intresse finns att se siffrorna och för min LIA-rapport hade lite skärmbilder från dashboarden suttit fint. 
