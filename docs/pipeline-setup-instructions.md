# Pipeline Setup Instructions
# OPEX Statistics — Daily Data Refresh

**Prepared by:** Michael Brostrom  
**For:** Intersolia IT / OPEX team

---

## Background

The OPEX Statistics Power BI report pulls data from two sources — Freshdesk and Linear.
Nightly snapshots are collected automatically via GitHub Actions and stored in a shared
GitHub repository. A daily refresh job then loads that data into the SQL Server database
(`InternalStatistics` on `INTSQLSERVER01`), where Power BI reads it.

**What is already automated (no action needed):**
- Nightly API snapshots (GitHub Actions, runs at midnight — fully hands-off)

**What needs to be set up once:**
- The daily database refresh (bronze + silver load) — this is what this document covers

There are two ways to set this up. Choose the one that fits best.

---

## Option A — Run on the operator's Windows machine (simpler)

The refresh script runs automatically on a Windows PC that has access to the
Intersolia network (office or VPN). This is the same setup already in use on
Michael's machine. If the PC is off or not on the network, the script retries
every hour when it next connects.

**Best if:** There is a Windows PC that is on most working days and has network
access to `INTSQLSERVER01`.

**Requirements:**
- Windows 10 or 11
- Network access to `INTSQLSERVER01` (direct or VPN)
- Internet access (to pull from GitHub)
- Administrator rights on the PC (for Task Scheduler registration only)

---

### Option A — Step-by-step setup

**Before you start — choose an installation folder**

Decide where the repository will be cloned on this PC. A good default is:
```
C:\Users\<YourUsername>\Documents\statistik-freshdesk-linear
```
Or any folder you prefer. We will call this `<REPO_PATH>` throughout these
instructions. Replace every `<REPO_PATH>` with your chosen folder as you go.

---

#### 1. Install Git for Windows
Download and install from: https://git-scm.com/download/win  
Accept all defaults during installation.

#### 2. Install Python 3.12
Download and install from: https://www.python.org/downloads/  
**Important:** tick "Add Python to PATH" on the first installer screen.

After installation, open a Command Prompt and run:
```
pip install requests pyodbc
```

#### 3. Install ODBC Driver 17 for SQL Server
Download from Microsoft:  
https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server  
Choose "ODBC Driver 17 for SQL Server" — the x64 installer.

#### 4. Get access credentials from Michael
Michael will provide two things separately:
- A **GitHub Personal Access Token (PAT)** — for read-only access to the repository
- The **SQL Server connection string** — for the database

Keep both safe. Treat them like passwords. Do not forward them by email.

#### 5. Clone the repository
Open a Command Prompt and run (replace `<TOKEN>` and `<REPO_PATH>`):
```
git clone https://Micke-Intersolia:<TOKEN>@github.com/Micke-Intersolia/statistik-freshdesk-linear.git <REPO_PATH>
```

#### 6. Create the credentials files
```
mkdir <REPO_PATH>\credentials
notepad <REPO_PATH>\credentials\sql_connection.txt
```
Paste the SQL Server connection string Michael provided. Save and close Notepad.

Then store the GitHub token for future reference (e.g. if the repo needs to be re-cloned on a new machine):
```
notepad <REPO_PATH>\credentials\github_token.txt
```
Paste the GitHub PAT Michael provided. Save and close Notepad.

These files are excluded from git — they exist only on this machine.

#### 7. Register the Task Scheduler task
Open PowerShell **as Administrator** and run (replace `<REPO_PATH>`):
```powershell
powershell -ExecutionPolicy Bypass -File "<REPO_PATH>\script\morning_refresh.ps1" -Register
```

Then open **Task Scheduler** and add hourly repetition:
1. Open Task Scheduler (search for it in the Start menu)
2. Find **"InternalStatistics - Daily Refresh"** in Task Scheduler Library
3. Right-click → **Properties** → **Triggers** tab
4. Select the trigger → **Edit**
5. Tick **"Repeat task every: 1 hour"** — Duration: **13 hours**
6. Click **OK** → **OK**

#### 8. Test
Right-click the task in Task Scheduler → **Run**.  
Then check the log file at `<REPO_PATH>\logs\refresh.log`.  
The last line should read:
```
[INFO]  Pipeline complete. Data is up to date.
```

---

## Option B — Run on the SQL Server (more robust)

The refresh script runs directly on `INTSQLSERVER01` as a SQL Server Agent job.
This is fully independent of any operator's machine — it runs on the server every
day at a fixed time regardless of who is logged in or connected.

**Best if:** IT can install Git and Python on `INTSQLSERVER01`, and the server
has outbound internet access to GitHub.

**Requirements (IT to confirm before starting):**
- SQL Server Agent service is enabled and running on `INTSQLSERVER01`
- Outbound HTTPS (port 443) from `INTSQLSERVER01` to `github.com` is permitted
- Git for Windows can be installed on `INTSQLSERVER01`
- Python 3.12 can be installed on `INTSQLSERVER01`
- The SQL Server Agent service account (or a proxy account) has write permissions
  to the chosen installation folder on the server

---

### Option B — Step-by-step setup

All steps below are performed on `INTSQLSERVER01` unless stated otherwise.

**Before you start — choose an installation folder**

Decide where the repository will be cloned on the server. Suggested locations
(use whichever fits your organisation's conventions):
```
C:\Apps\statistik-freshdesk-linear
C:\Scripts\statistik-freshdesk-linear
D:\Apps\statistik-freshdesk-linear        (if applications live on D:)
```
Avoid `C:\Program Files` (requires elevated rights for every git pull).  
We will call the chosen path `<REPO_PATH>` throughout these instructions.

**Important:** The SQL Server Agent service account must have read/write access
to `<REPO_PATH>`. IT should create this folder and grant the service account
full control before proceeding.

---

#### 1. Install Git for Windows (on the server)
Download and install from: https://git-scm.com/download/win  
Accept all defaults.

#### 2. Install Python 3.12 (on the server)
Download from: https://www.python.org/downloads/  
Tick **"Add Python to PATH"**. After installation, open a Command Prompt and run:
```
pip install requests pyodbc
```

#### 3. Get access credentials from Michael
Michael will provide:
- A **GitHub Personal Access Token (PAT)** — read-only access to the repository
- The **SQL Server connection string** — for the database

#### 4. Clone the repository (on the server)
Open a Command Prompt **as the SQL Server Agent service account** (or as an
administrator, then verify the service account can also read the folder).  
Run (replace `<TOKEN>` and `<REPO_PATH>`):
```
git clone https://Micke-Intersolia:<TOKEN>@github.com/Micke-Intersolia/statistik-freshdesk-linear.git <REPO_PATH>
```

#### 5. Create the credentials files (on the server)
```
mkdir <REPO_PATH>\credentials
notepad <REPO_PATH>\credentials\sql_connection.txt
```
Paste the SQL Server connection string, save and close.

Then store the GitHub token for future reference:
```
notepad <REPO_PATH>\credentials\github_token.txt
```
Paste the GitHub PAT, save and close.

These files are excluded from git — they exist only on the server.

#### 6. Verify the script runs manually
Open PowerShell on the server and run (replace `<REPO_PATH>`):
```powershell
powershell -ExecutionPolicy Bypass -File "<REPO_PATH>\script\morning_refresh.ps1"
```
Check the log at `<REPO_PATH>\logs\refresh.log`.  
The last line should read `[INFO]  Pipeline complete. Data is up to date.`  
Fix any errors before setting up the Agent job.

#### 7. Create the SQL Server Agent job
Open **SQL Server Management Studio (SSMS)** and connect to `INTSQLSERVER01`.

In Object Explorer:
1. Expand **SQL Server Agent** → right-click **Jobs** → **New Job...**

2. **General tab:**
   - Name: `InternalStatistics - Daily Refresh`
   - Description: `Runs git pull, bronze_loader.py and silver_loader.py to refresh the BI database.`

3. **Steps tab** → click **New...**:
   - Step name: `Run morning_refresh.ps1`
   - Type: **Operating system (CmdExec)**
   - Run as: SQL Server Agent service account (or a configured proxy)
   - Command (replace `<REPO_PATH>`):
     ```
     powershell.exe -NonInteractive -ExecutionPolicy Bypass -File "<REPO_PATH>\script\morning_refresh.ps1"
     ```
   - On success: `Go to the next step` / On failure: `Quit the job reporting failure`
   - Click **OK**

4. **Schedules tab** → click **New...**:
   - Name: `Daily weekdays 07:00`
   - Schedule type: **Recurring**
   - Frequency: **Daily** — every 1 day
   - Daily frequency: **Occurs once at 07:00:00**
   - Start date: today
   - Click **OK**

5. **Notifications tab** (optional but recommended):
   - Tick **"Write to the Windows Application event log"** → on job failure

6. Click **OK** to save the job.

#### 8. Test the job
In SSMS: right-click the job → **Start Job at Step...**  
Monitor: right-click the job → **View History**  
Also check `<REPO_PATH>\logs\refresh.log` — last line should read:
```
[INFO]  Pipeline complete. Data is up to date.
```

---

## Verifying the pipeline is working (either option)

1. **Log file** — last line:
   ```
   [INFO]  Pipeline complete. Data is up to date.
   ```

2. **Last success file** at `<REPO_PATH>\logs\last_success.txt` — should contain today's date.

3. **SQL Server** — in SSMS, run:
   ```sql
   SELECT TOP 1 _loaded_at FROM bronze.linear_issues ORDER BY _loaded_at DESC;
   SELECT TOP 1 _loaded_at FROM bronze.freshdesk_tickets ORDER BY _loaded_at DESC;
   ```
   Both should show today's date.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Database unreachable` in log | VPN not connected / server down | Connect VPN and wait for next retry |
| `git pull failed` in log | Token expired or network blocked | Renew PAT (contact Michael) or check firewall |
| `bronze_loader.py failed` | Python not found or pyodbc missing | Verify Python is on PATH; re-run `pip install pyodbc` |
| `silver_loader.py failed` | SQL error in silver scripts | Check log for the error message; contact Michael |
| Job runs but no new data | All files already loaded (normal) | Check if GitHub Actions ran — snapshot files may not have changed |

---

## Contact

For questions about this setup: **Michael Brostrom** — michael.brostrom@intersolia.com
