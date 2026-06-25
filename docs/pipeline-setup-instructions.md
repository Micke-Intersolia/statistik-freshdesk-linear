# Instruktioner för daglig datauppdatering
# OPEX Statistics — Pipeline-setup

**Framtagen av:** Michael Brostrom  
**För:** Intersolia IT / OPEX-teamet

---

## Bakgrund

Power BI-rapporten OPEX Statistics hämtar data från två källor — Freshdesk och Linear.
Nattliga snapshots samlas in automatiskt via GitHub Actions och lagras i ett delat
GitHub-repository. Ett dagligt uppdateringsjobb läser sedan in denna data i SQL Server-databasen
(`InternalStatistics` på `INTSQLSERVER01`), varifrån Power BI hämtar sina data.

**Vad som redan är automatiserat (ingen åtgärd krävs):**
- Nattliga API-snapshots (GitHub Actions, körs vid midnatt — helt hands-off)

**Vad som behöver konfigureras en gång:**
- Den dagliga databasuppdateringen (bronze + silver load) — det är vad detta dokument handlar om

Det finns två sätt att konfigurera detta. Välj det alternativ som passar bäst.

---

## Alternativ A — Kör på en Windows-dator (enklare)

Uppdateringsskriptet körs automatiskt på en Windows-dator som har tillgång till
Intersolias nätverk (kontor eller VPN). Det är samma konfiguration som redan används på
min dator. Om datorn är av eller inte är ansluten till nätverket försöker skriptet
igen varje timme när det väl ansluts.

**Välj detta om:** Det finns en Windows-dator som är påslagen de flesta arbetsdagar och har
nätverksåtkomst till `INTSQLSERVER01`.

**Krav:**
- Windows 10 eller 11
- Nätverksåtkomst till `INTSQLSERVER01` (direkt eller via VPN)
- Internetåtkomst (för att hämta från GitHub)
- Administratörsbehörighet på datorn (endast för registrering av schemaläggaren)

---

### Alternativ A — Steg-för-steg

**Välj installationsmapp**

Bestäm var i filsystemet du vill klona repositoryt. Jag har kört med
```
C:\Users\<DittAnvändarnamn>\Documents\statistik-freshdesk-linear
```
Eller valfri annan mapp. Jag kallar den `<REPO_PATH>` i dessa instruktioner.
Ersätt varje `<REPO_PATH>` med din valda sökväg.

---

#### 1. Installera Git for Windows
Ladda ner och installera från: https://git-scm.com/download/win  

#### 2. Installera Python 3.12
Ladda ner från: https://www.python.org/downloads/  
**Viktigt:** Kryssa i **"Add Python to PATH"** på den första installationsskärmen.

Öppna sedan en kommandotolk och kör:
```
pip install requests pyodbc
```

#### 3. Installera ODBC Driver 17 for SQL Server
Ladda ner från Microsoft:  
https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server  
Välj "ODBC Driver 17 for SQL Server" — x64-installationsprogrammet.

#### 4. Använd inloggningsuppgifterna som kommer i separata filer
- En **GitHub Personal Access Token (PAT)** — för läsbehörighet till repositoryt
- **SQL Server-anslutningssträngen** — för databasen

#### 5. Klona repositoryt
Öppna en kommandotolk och kör (ersätt `<TOKEN>` och `<REPO_PATH>`):
```
git clone https://Micke-Intersolia:<TOKEN>@github.com/Micke-Intersolia/statistik-freshdesk-linear.git <REPO_PATH>
```

#### 6. Lägg till credentials-mappen
Michael tillhandahåller en zippad `credentials`-mapp. Extrahera den direkt till `<REPO_PATH>` så att resultatet blir:
```
<REPO_PATH>\credentials\sql_connection.txt
<REPO_PATH>\credentials\github_token.txt
```
Dessa filer är undantagna från git-repot så använd de två du får här.

#### 7. Registrera schemaläggaren
Öppna PowerShell **som Administratör** och kör (ersätt `<REPO_PATH>`):
```powershell
powershell -ExecutionPolicy Bypass -File "<REPO_PATH>\script\morning_refresh.ps1" -Register
```

Skriptet försöker sätta timrepetitionen automatiskt. Om det lyckades skriver det ut `Schedule: weekdays 07:00-20:00, every hour` — du är klar.

Om det i stället skriver ut manuella steg, gör så här i **Schemaläggaren (Task Scheduler)**:
1. Öppna Schemaläggaren (sök i startmenyn)
2. Hitta **"InternalStatistics - Daily Refresh"** i Schemaläggningsbiblioteket
3. Högerklicka → **Egenskaper** → fliken **Utlösare**
4. Markera utlösaren → **Redigera**
5. Kryssa i **"Upprepa uppgift var: 1 timme"** — Varaktighet: **13 timmar**
6. Klicka **OK** → **OK**

#### 8. Testa
Högerklicka på uppgiften i Schemaläggaren → **Kör**.  
Kontrollera sedan loggfilen på `<REPO_PATH>\logs\refresh.log`.  
Sista raden ska vara:
```
[INFO]  Pipeline complete. Data is up to date.
```

---

## Verifiera att pipelinen fungerar

1. **Loggfilen** — sista raden:
   ```
   [INFO]  Pipeline complete. Data is up to date.
   ```

2. **Senaste lyckade körning** i `<REPO_PATH>\logs\last_success.txt` — ska innehålla dagens datum.

3. **SQL Server** — kör i SSMS:
   ```sql
   SELECT TOP 1 _loaded_at FROM bronze.linear_issues ORDER BY _loaded_at DESC;
   SELECT TOP 1 _loaded_at FROM bronze.freshdesk_tickets ORDER BY _loaded_at DESC;
   ```
   Båda ska visa dagens datum.

---

## Felsökning

| Symptom | Trolig orsak | Åtgärd |
|---|---|---|
| `Database unreachable` i loggen | VPN ej ansluten / servern nere | Anslut VPN och vänta på nästa försök |
| `git pull failed` i loggen | Token utgången eller nätverk blockerat | Förnya PAT (kontakta Michael) eller kontrollera brandvägg |
| `bronze_loader.py failed` | Python hittades inte eller pyodbc saknas | Verifiera att Python finns i PATH; kör `pip install pyodbc` igen |
| `silver_loader.py failed` | SQL-fel i silver-skripten | Kontrollera felmeddelandet i loggen; kontakta Michael |
| Jobbet körs men ingen ny data | Alla filer redan inladdade (normalt) | Kontrollera om GitHub Actions körde — snapshot-filerna kanske inte har ändrats |

---

## Kontakt

Frågor: **Michael Brostrom** — michael.brostrom@intersolia.com / puttaren@gmail.com (backup)
