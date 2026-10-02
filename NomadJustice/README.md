# NomadJustice v8.1.0

Department of Justice suite for QBCore: citizen records, department management, cases, duty clock, lockers, evidence archive, compensation and the DOJ motor pool.

## Installation
1. Copy the `NomadJustice` folder into `resources`.
2. Add `ensure NomadJustice` to `server.cfg` **after** its dependencies:
   - `oxmysql`
   - `ox_lib`
   - `qb-core`
   - `deep-target`
   - `deep-Banking`
   - `deep-inventory`
   - The target resource name can be changed with `TargetResource` in `config.lua`, the core name with `setr justice_core "qb-core"`, the bank with `Finance.Resource` and the inventory with `InventoryResource`.
3. Tables are created and migrated automatically on start. You can also install them manually from **`NomadJustice.sql`** (safe to run more than once, never deletes data).
4. (Optional) Discord: `set justice_webhook "https://discord.com/api/webhooks/..."` in `server.cfg`.

## Files you edit
| File | Contains |
|---|---|
| `modules/coords.lua` | **All coordinates**, each line has a name and a type |
| `modules/config.lua` | Fees, permissions, limits, vehicles, ped appearance, finance |

### Coordinates
```lua
{ name = 'Courthouse Locker', type = 'Stash', coords = vector4(X, Y, Z, heading) },
```
- Types: `'Duty'` `'Stash'` `'Case Files'` `'Citizen Panel'` `'Case Clerk'` `'Motor Pool Clerk'` `'Vehicle Spawn'` `'Blip'`
- `/jcoords` in game copies your current position ready to paste
- A wrong type prints the line number and name in the console
- Same coordinates for several types = their options are merged into one point
- Option not showing? Set `DebugZones = true` or increase `ZoneSize` in `config.lua`

## 📱 State Records (tablet)
- Opens with **key 9** anywhere (or `/justice`). Players can rebind it in Settings → Key Bindings → FiveM.
- Custom NUI (not ox_lib menus): dashboard, online players, citizen registry, search, full citizen record, cases, departments, city affairs, summonses, suspended citizens and the audit log.
- Tablet holding animation while open; close with **ESC** or ✕.
- Legacy menus: `UseTablet = false` in `config.lua`. Change the key with `Key = '9'`.
- **Security:** the UI only displays data. All checks and permissions run on the server, and all text is rendered as text so nothing typed in a name or case can execute.

## 👥 Roles in State Records
| Role | Sees |
|---|---|
| ⚖️ **DOJ** | Everything (per permissions) |
| 🚓 **Police** (`Settings.Police.Jobs`) | Search, basic info, licenses, vehicles, **case & verdict history**, active warrants, persons of interest, their requests |
| 💼 **Attorney** (holds the `lawyer` license) | Only the cases they are assigned to: details, notes, documents, verdicts |
| 💰 **Department manager** (`Finance.Sectors`) | Department finances only |

## 🎖️ Default permissions by grade
The DOJ job is **`judge`** (Judicial Department). **Rule:** number = this grade and above. Grades **11 Chief Justice** and **12 Supreme Court Justice** have everything. All of this is configurable in `config.lua`.

| Judicial Department | Permissions |
|---|---|
| 0 Trainee and above | Search, citizen records, cases, city affairs |
| 1 Court Clerk | + summonses, licenses and bar license |
| 4 Prosecutor | + locate, persons of interest |
| 8 Junior Judge | + verdicts, warrants, police requests, attorneys, statistics, identity edits, announcements, audit log, city economy, delete cases |
| 9 Judge | + bank seizure, suspensions, vehicles, properties, gangs, compensation |
| 10 Senior Judge | same as Judge |
| 11 Chief Justice | **Everything** (see below) |
| 12 Supreme Court Justice | **Everything** (see below) |

| Police | Permissions |
|---|---|
| 0 Cadet and above | Search, basic info, case & verdict history, warrants, persons of interest |
| 2 Officer I | + citizen vehicles |
| 3 Officer II | + log warrant execution |
| 6 Sergeant | + request DOJ authorization (location, bank statement, warrant) |

## 👑 Chief Justice (11) and Supreme Court Justice (12)
**Full access to everything in State Records**:
- **Justice:** every permission (verdicts, undo, delete, warrants, job and grade control in every department...).
- **Police:** every police permission (search, records, vehicles, warrants, **warrant execution**, persons of interest, requests); all police requests reach them.
- **EMS and Police finances:** balance, withdraw, deposit and history for every department, selected at the top.
- **Oversight:** the full audit log of every department, plus statistics, duty log and evidence archive.
- **Unlimited compensation:** they are the only grades that may compensate **themselves**, with no per-transaction, daily or distance limit (permission `unlimitedCompensation = 11`). Every payout is still written to the audit log as `Compensation (self)`. A technical ceiling of `CompensationHardCap` per transaction protects the database.

The tablet shows "👑 Full access - Justice, Police & EMS". The grade number is `Settings.Panel.FullAccessGrade` (11).

## 🛡️ Abuse protection
- **Rate limit:** 25 requests per player every 5 seconds. Executors flooding the server are blocked and flagged in the console.
- **Unauthorized attempts:** anyone without a role calling the system's callbacks is printed with their name and citizen ID.
- **Money:** every balance is checked server-side, with cooldowns, no double undo, and the internal fund never goes negative.

## 💰 Department finances
- **Who:** only the listed managers see the **department balance**, withdraw and deposit, with a full transaction history:
  - **Police:** 13 Deputy Police Chief, 14 Police Chief, 15 Deputy Minister of Interior, 16 Minister of Interior.
  - **EMS:** 11 Deputy EMS Chief, 12 EMS Chief.
- **Where:** police managers get an extra section in the police view; EMS managers open the tablet with key 9 and see finances only.
- **Balance source (`Finance.Provider = 'auto'`):**
  - **deep-Banking** business accounts (`getBusinessAccount` / `AddMoney` / `RemoveMoney`), the default `Finance.Resource`.
  - Otherwise qb-style or Renewed-style banking exports if detected.
  - Otherwise an internal fund in the database (`justice_sector_funds`).
  - The startup readiness report shows which one is active.
- **Oversight:** every transaction is written to the DOJ audit log; grades 11 and 12 see and manage every department's finances.
- **Add a department:** `Finance.Sectors`.

## 🚓 Police section
- Police permissions are set per grade in `Settings.Police.Permissions`: number = lowest grade, `'boss'` = command staff, `false` = locked.
- **Sensitive actions need a DOJ authorization request:** locate, bank statement, arrest warrant or search warrant. The request reaches the DOJ with the officer's name, grade, callsign and reason.
- In the DOJ **Police Requests** page, approve or reject with a note:
  - **Locate:** the officer receives a map blip.
  - **Bank statement:** access is granted for `GrantMinutes` minutes.
  - **Arrest / search warrant:** issued automatically, recording who requested it.
- Officers log warrant execution from the tablet.

## 🔨 Verdicts (enforced automatically)
From a citizen record or a case page → **Issue Verdict**:
| Verdict | Enforcement |
|---|---|
| Fine | Taken from the defendant's bank and routed by `WithdrawTo` |
| Damages | Taken from the defendant's bank and paid into the plaintiff's bank |
| Vehicle impound | Impounded and removed from the street (must be registered to them) |
| Jail | Recorded and sent to police. If you have a jail script, set its event in `JailEvent` |
| Service suspension | Their services are suspended |
| Acquittal | Recorded |

- Every verdict is stored in the citizen's **verdict history**, visible to DOJ and police, and the case closes automatically.
- **Reverse a verdict:** Audit Log → ↩️ Undo. Refunds both parties, releases the vehicle and lifts the suspension.

## 🚨 Warrants and 🕵️ persons of interest
- **Warrants** are pushed to on-duty police instantly and show as a red alert on the citizen record until they expire (`WarrantHours`), are revoked or executed.
- **Persons of interest:** a list with threat level. A **high** threat level alerts police immediately.

## 📊 Statistics and 🔔 notifications
- **Statistics:** cases per week, top case types, verdicts by type, staff performance and duty hours. Every chart has a "Table" toggle.
- **Live notifications:** new case, police request, new warrant, request answered. Shown inside the tablet with a sound, or as a regular notification when the tablet is closed.

## 🏦 Bank
- Citizen money (seizures, fines, compensation) uses the qb-core player bank balance.
- **Where seized money goes:** `WithdrawTo = 'officer'` (your account), `'society'`, or `'none'`.
- Department accounts use **deep-Banking** (see Department finances).

## ↩️ Undo and delete
From the **Audit Log** (tablet, or the "Log" tab of a citizen record):
- **↩️ Undo:** reverts the action. Covers seizures (refund), compensation, suspensions, identity edits, jobs, duty, gangs, licenses, impounds, vehicle and property transfers, summonses and case status.
- **🗑️ Delete:** removes the record or summons, leaving a trace of who deleted what.
- An action cannot be undone twice, even if two employees click at the same moment.
- `undo` and `delete` default to grades 11 and 12.

## Citizen records
Opened with key 9 or `/justice`.

| Feature | Default permission |
|---|---|
| Live status: 🟢 Online [server ID] - joined ... ago / ⚫ Offline - last seen ... ago | Any employee |
| Citizen registry (paged) with filter: all / online / offline | Any employee |
| Dashboard: online, citizens, DOJ on duty, new cases, suspended | Any employee |
| Online players and search (name / citizen ID / phone / server ID, offline included) | Any employee |
| Citizen record: identity, finances, employment & gang, jail & criminal record, licenses, vehicles, properties, possessions, cases, DOJ actions | Any employee |
| Departments: every department and its staff (online / on duty / total) | Any employee |
| **Change any citizen's job and grade**, hire, promote, demote, transfer, terminate, clock in/out | Chief Justice |
| Locate | Prosecutor |
| Bank seizure (with reason, works online and offline) | Judge |
| Suspend / lift services | Judge |
| Edit identity | Junior Judge |
| Compensation (daily cap per employee) | Judge |
| Self compensation, no limits | Chief Justice / Supreme Court Justice only |
| Audit log | Junior Judge |

Permissions live in `Settings.Panel.Permissions` (number = lowest grade, or `'boss'`). All actions require the employee to be on duty (`RequireDuty`).
To protect a department (e.g. admin), add it to `JobsBlacklist`.

## City affairs
| Feature | Default permission |
|---|---|
| City status: online, citizens, suspended, summonses, departments on duty | Any employee |
| Vehicle registry: search by plate or citizen ID, owner and status, on the street or not | Any employee |
| Property registry: search by name or citizen ID, owner | Any employee |
| Locate a vehicle on the street | Judge |
| Impound (removed from the street), release, transfer title | Judge |
| Transfer property deed | Judge |
| Grant / revoke licenses | Court Clerk |
| Change / remove gang | Judge |
| Court summons (delivered instantly, or on next join) + follow-up: appeared / failed to appear / cancelled | Court Clerk |
| City economy: total bank and cash, top 10 richest citizens (live balances for online players) | Junior Judge |
| City-wide announcement | Junior Judge |

Citizens see their summonses at the Court Clerk ped → **My Summonses**.

## Cases
- Citizens fill in title, type, defendant, witnesses, evidence and details, then confirm before the fee is charged.
- Plaintiff details are collected server-side and cannot be forged: date of birth, sex, nationality, job, gang, account, filing location.
- Staff: filter by status, change status, notes, open plaintiff / defendant records, mark filing location, delete.
- Citizens track their lawsuits and get notified on every status change.

## Hooking suspensions into other scripts
```lua
if exports['NomadJustice']:IsCitizenSuspended(citizenid) then return end
AddEventHandler('NomadJustice:server:suspensionChanged', function(citizenid, suspended, reason) end)
```

## Automatic cleanup
`Settings.Cleanup` deletes old records so the database stays light: audit log after 120 days, duty log after 60 days. Closed cases are only deleted if you enable it. `0` = never delete.

## Readiness check
On start the script prints a report to the server console: what is fine (✔), warnings (⚠) and what must be fixed (✖). It covers dependencies, the DOJ job and grades, tables, finance provider and Discord.
Run it again any time with **`justicecheck`** in the server console.

## Common mistakes handled automatically
- **Syntax error in `coords.lua` or `config.lua`** (missing comma or brace): prints the file name and line number, the script keeps running.
- **Bad coordinates line:** skipped on its own with its number and name printed; the rest works.
- **Missing or invalid setting:** falls back to the default with a warning.
- **Server did not respond:** menus never hang; a message appears after 10 seconds.
- **Double clicks:** a request is never sent twice.
- **Optional resource missing** (lb-phone): only the related feature stops.
- **Discord:** messages are queued one every 1.5 seconds so the webhook is never rate-limited.

## Testing
Every system was tested against a real MariaDB database with QBCore tables and the actual script code: 232 database checks pass, covering police, attorneys, verdicts, warrants, banking and deep-Banking business accounts. The UI was tested in Chromium for every role (DOJ, police, attorney, department manager) with zero errors, and upgrading from the original tables keeps all old data.

## Security
- **Server-side validation of everything:** permission, duty, input values, amount limits, and no actions on yourself.
- **Database:** every query is parameterized (no SQL injection). Offline edits fail safely if the player's data changes mid-operation.
- **Text sanitizing:** image links and HTML that could leak staff IPs are blocked, and malformed UTF-8 is rejected.
- **Spam:** click protection, cooldowns and a daily compensation cap.
- **Logs:** every action is written to `justice_logs` and sent to Discord when enabled.

### Lockers (deep-inventory)
Lockers and the evidence archive are opened **by the server** through `exports['deep-inventory']:OpenInventory(source, stashId, { label, maxweight, slots })` after it checks the job (and management / grade 11+ for the archive). If the inventory has no such export, it falls back to the classic `inventory:server:OpenInventory` event.
