# Education Voicemail — Build Guide (As-Built)

> **As-built revision.** This supersedes `Education_Voicemail_Build_Guide_v2.pdf`. Steps that
> changed during the actual build are marked **[AS-BUILT]**. Phase 1 is complete and validated.

| | |
|---|---|
| Toolchain | Claude Code · Salesforce CLI (sf) v2 · Git · API v62.0 |
| Sandbox | `gormecasemgmt@ed.sc.gov` (casemgmt) |
| Project dir | `Voicemail/` (SFDX project; `force-app`, `sourceApiVersion 62.0`) |
| Convention | write metadata → commit → deploy → test |

> **[AS-BUILT] Environment note:** on this Windows machine `sf` was not on PATH in the
> non-interactive shell; commands were run as `& "C:\Program Files\sf\bin\sf.cmd" …`. In a normal
> terminal where `sf` resolves, use the plain `sf …` commands shown below.

---

# PHASE 1 — SALESFORCE

Phase 1 is complete when a Case can be created in the Education Voicemail queue with both custom
fields populated, a `.wav` attached and playable, and the dedup flow firing. **All validated.**

## STEP 1 — SFDX Project & Git
Project already initialized at `Voicemail/` with `sourceApiVersion: 62.0`.
> ⚠️ **[AS-BUILT] Git status:** the Phase 1 build is **not yet committed**. Commit before handoff.

## STEP 2 — Case Custom Fields ✅
Files:
```
force-app/main/default/objects/Case/fields/
  Callback_Number__c.field-meta.xml   (Phone)
  Caller_Name__c.field-meta.xml        (Text 255)
  External_Id__c.field-meta.xml        [AS-BUILT] Text(255), External ID, Unique
```
```bash
sf project deploy start --source-dir force-app/main/default/objects/Case --target-org gormecasemgmt@ed.sc.gov
```
**Test (confirmed):** both fields present with correct types; a Case saved with both values.
> **[AS-BUILT] FLS gotcha:** metadata-deployed fields have **no field-level security** by default,
> so even an admin can't see them until the permission set (Step 6) grants FLS. This blocked the
> first create attempt; resolved by deploying + assigning `Education_Voicemail_Agent`.
> **[AS-BUILT] `External_Id__c` added here** (was a Phase 2 dependency the original spec never created).

## STEP 2.5 — Record Type & Business Process ✅ **[AS-BUILT — NEW STEP]**
Added so the Voicemail layout scopes to voicemail Cases only (not all Case types on a profile).
```
force-app/main/default/objects/Case/businessProcesses/Voicemail_Process.businessProcess-meta.xml
force-app/main/default/objects/Case/recordTypes/Voicemail.recordType-meta.xml
```
```bash
sf project deploy start --source-dir force-app/main/default/objects/Case/businessProcesses force-app/main/default/objects/Case/recordTypes --target-org gormecasemgmt@ed.sc.gov
```
- Record Type Id: **`012WA000001OMMzYAO`** · Business process Status values: New (default), In Progress, Closed, Escalated, Critical, On Hold.
- Case record types **require** a business process — that's why both were deployed together.
- **Phase 2 impact:** Python API must set `RecordTypeId`; integration user needs the record type (granted via perm set).

## STEP 3 — Queue ✅
```
force-app/main/default/queues/Education_Voicemail.queue-meta.xml
```
```bash
sf project deploy start --source-dir force-app/main/default/queues --target-org gormecasemgmt@ed.sc.gov
```
**Test (confirmed):** queue present, supports Case. **Queue ID = `00GWA000007oHmP2AU`.**
> Add Education staff as **queue members** manually (not in metadata). Decide whether
> "All Internal Users" (selected during setup) is intended or should be trimmed to Education staff.

## STEP 4 — Case Page Layout ✅
```
force-app/main/default/layouts/Case-Voicemail_Case_Layout.layout-meta.xml
```
```bash
sf project deploy start --source-dir force-app/main/default/layouts --target-org gormecasemgmt@ed.sc.gov
```
**Sections:** Case Information (Subject, Status[Required], Origin, OwnerId, CreatedDate, **+[AS-BUILT]** ContactId, Priority, Description, SuppliedName/Email/Phone/Company) · Voicemail Details (`Callback_Number__c`, `Caller_Name__c`) · Files related list (`RelatedFileList`).
> **[AS-BUILT] Required-field fixes:** the deploy failed until ContactId, Priority, Description and
> the Supplied* fields were added and Status set to Required — the org requires them on a Case layout.
>
> **[AS-BUILT] Lightning record page (App Builder), not just the layout:**
> 1. Add a **Related Lists** (or Files) component — the stock console page used pinned
>    single-related-list components that excluded Files.
> 2. Add the **Voicemail Audio Player** component (Custom section) for inline `.wav` playback.
> 3. **Save → Activate** and assign the page for the relevant app/record type/profile, or new
>    Cases won't get it.
>
> **[AS-BUILT] Layout assignment:** set the **Voicemail record-type column only** for the agent
> profile(s). Do **not** switch all columns (that overrides their normal Case layout).
>
> **[AS-BUILT] `.wav` playback:** native file preview shows "No preview available" for audio — this
> is a platform limit, not a defect. Inline playback is via the audio-player LWC (Step 6.5);
> download-and-play also works.

## STEP 5 — Deduplication Flow ✅
```
force-app/main/default/flows/Education_Voicemail_Deduplicate_Check.flow-meta.xml
```
```bash
sf project deploy start --source-dir force-app/main/default/flows --target-org gormecasemgmt@ed.sc.gov
```
After-save / insert-only on Case; entry Origin='Phone' AND `Callback_Number__c` not null; finds
other open Cases with same callback; adds a Case Comment; no close/merge. **Active.**
> **[AS-BUILT] Comment body** references `CaseNumber` (Cases have no `Name`):
> `"Possible duplicate — an open case already exists for this callback number. See Case " + CaseNumber`.
> **Test (confirmed):** two Phone Cases, same callback → 2nd gets the comment referencing the 1st;
> neither closed. Verified both via Apex and live in the UI.

## STEP 6 — Permission Set ✅
```
force-app/main/default/permissionsets/Education_Voicemail_Agent.permissionset-meta.xml
```
```bash
sf project deploy start --source-dir force-app/main/default/permissionsets --target-org gormecasemgmt@ed.sc.gov
sf org assign permset --name Education_Voicemail_Agent --target-org gormecasemgmt@ed.sc.gov
```
Grants (all **[AS-BUILT]** beyond the original two-field spec):
- Read+Edit on `Callback_Number__c`, `Caller_Name__c`, **`External_Id__c`**
- **Record type** `Case.Voicemail` visible
- **Apex class** `VoicemailAudioController` enabled
> **Test (confirmed via metadata):** Read+Edit on all three fields, assigned. **Login-as test:** to
> validate visually, a **non-admin** agent (e.g. SCDE Constituent Manager) needs the perm set **and**
> the Voicemail layout assigned to their profile for the Voicemail record type. Field visibility has
> two gates: **FLS (perm set)** + **layout placement**.

## STEP 6.5 — Voicemail Audio Player (LWC) ✅ **[AS-BUILT — NEW STEP]**
```
force-app/main/default/classes/VoicemailAudioController.cls (+ test, + meta)
force-app/main/default/lwc/voicemailAudioPlayer/  (js, html, js-meta.xml)
```
```bash
sf project deploy start --source-dir force-app/main/default/classes force-app/main/default/lwc force-app/main/default/permissionsets --test-level RunSpecifiedTests --tests VoicemailAudioControllerTest --target-org gormecasemgmt@ed.sc.gov
```
HTML5 `<audio>` player streaming the latest `.wav` ContentVersion on the Case. Apex test passing.
Place on the Voicemail record page (App Builder). **Confirmed playing inline.**

## STEP 7 — Phase 1 Validation ✅ (all confirmed)

| Check | Result |
|---|---|
| Custom fields exist | `Callback_Number__c` Phone, `Caller_Name__c` Text(255) ✅ |
| Queue exists | Education Voicemail, Case; ID `00GWA000007oHmP2AU` ✅ |
| Layout works | Voicemail Details + Files visible ✅ |
| `.wav` attachment | Uploads to Files; plays inline via LWC (native preview can't) ✅ |
| Dedup flow fires | Comment on 2nd Case referencing 1st; neither closed ✅ |
| Permission set | R/E on fields confirmed; login-as needs layout+perm set on agent profile ✅ |

### 7.2 Phase 2 handoff
| Item | Value | Status |
|---|---|---|
| `Callback_Number__c` | `Callback_Number__c` | ✅ |
| `Caller_Name__c` | `Caller_Name__c` | ✅ |
| `External_Id__c` **[AS-BUILT]** | `External_Id__c` | ✅ |
| Queue ID | `00GWA000007oHmP2AU` | ✅ |
| Record Type Id **[AS-BUILT]** | `012WA000001OMMzYAO` | ✅ |
| Mailbox IMAP (`estfvoicemail@ed.sc.gov`, Office 365 / IMAP) | — | ☐ M365 admin |
| Connected App / Anypoint / Azure / API key | — | ☐ external owners |

See `PHASE2_HANDOFF.md` for the live handoff checklist.

---

# PHASE 2 — PYTHON API + MULESOFT

Unchanged from the original guide **except** the Case create mapping now includes
**`RecordTypeId = 012WA000001OMMzYAO`** (Step 9.1 / 10.5), and `External_Id__c` already exists.
Steps 8–11 (FastAPI scaffold, endpoints, MuleSoft flow, end-to-end test) proceed once the
external prerequisites above are confirmed.

## Quick Reference — deploy commands
```bash
# validate / deploy any folder (replace the path; no angle brackets)
sf project deploy start --dry-run --source-dir force-app/main/default/layouts --target-org gormecasemgmt@ed.sc.gov
sf project deploy start        --source-dir force-app/main/default/layouts --target-org gormecasemgmt@ed.sc.gov
# whole project
sf project deploy start --source-dir force-app --test-level RunLocalTests --target-org gormecasemgmt@ed.sc.gov
```
