# Education Voicemail — Technical Requirements (As-Built)

> **As-built revision.** This supersedes the original `Education_Voicemail_Requirements_v2.pdf`.
> Changes made during the Phase 1 build are marked **[AS-BUILT]**. Phase 1 is complete and
> validated in the **casemgmt** sandbox (`gormecasemgmt@ed.sc.gov`), API v62.0.

**Assigned to:** Gavin
**Phase 1:** Salesforce (fields, queue, layout, record type, flow, permission set)
**Phase 2:** Python API layer (MuleSoft → Python → Salesforce)

---

## Overview

When a caller leaves a voicemail for the Education program, a Salesforce Case is automatically
created in the Education Voicemail queue — no manual action required. The Case is pre-populated
with the caller's name, phone number, timestamp, and the original `.wav` recording attached.

Built in two phases. Phase 1 establishes the Salesforce data model — everything that must exist
before any code touches the org. Phase 2 adds the Python API layer and MuleSoft flow.

Transcription is out of scope for both phases (revisited once Azure AI Speech is confirmed).

## Architecture

```
Segra Voicemail System
   │
   ▼
Forwarded Email (.wav attachment)
   │
   ▼
MuleSoft (Anypoint Platform)      ← Phase 2
   │ parses subject, extracts .wav
   ▼
Python API (FastAPI on Azure)     ← Phase 2
   │ OAuth 2.0 client credentials
   ▼
Salesforce Service Cloud          ← Phase 1
```

## Inbound Email Structure (Phase 2 Reference)

| Field | Value |
|---|---|
| From | voicemessage@voipmsg.us |
| To | [Education Mailbox Display Name] <[EDUCATION_MAILBOX_VOIP_ADDRESS]> |
| Cc | [Staff Name] <estfvoicemail@ed.sc.gov> (monitored mailbox) |
| Subject | [EXTERNAL] Voice Message Attached from {10-digit-phone} - {Caller Name} |
| Body | Time: {Date} {Time} / Click attachment to listen to Voice Message |
| Attachment | .wav audio file |

Subject line is the primary data source. Parse phone + caller name from:
`"Voice Message Attached from {10-digit-phone} - {Caller Name}"`

---

# Phase 1 — Salesforce Requirements

## Custom Fields on Case

| Field Label | API Name | Type | Notes |
|---|---|---|---|
| Callback Number | `Callback_Number__c` | Phone | 10-digit caller phone from subject |
| Caller Name | `Caller_Name__c` | Text(255) | Caller name from subject |
| **External ID** **[AS-BUILT]** | `External_Id__c` | Text(255), External ID, Unique | Idempotency key. **Moved into Phase 1** — the original doc only referenced it in the Phase 2 mapping but never created it. Phase 2's idempotency query (`WHERE External_Id__c = …`) and the create mapping both require it, so it was built in Phase 1. Unique constraint also gives a DB-level dedupe safety net. |

> **[AS-BUILT] FLS caveat:** Fields deployed via metadata get **no field-level security** by
> default — not even for System Administrator. Access is granted through the
> `Education_Voicemail_Agent` permission set (below). Anyone who needs to see/edit these fields
> (including the Phase 2 integration user) must have that perm set or equivalent FLS.

## Queue

| Setting | Value |
|---|---|
| Label | Education Voicemail |
| Queue Name (API) | `Education_Voicemail` |
| Supported Objects | Case |
| Queue Members | Education program staff (added manually in Setup) |
| **Queue ID [AS-BUILT]** | **`00GWA000007oHmP2AU`** (maps to Case `OwnerId` in Phase 2) |

## Case Record Type **[AS-BUILT — NEW, not in original spec]**

A dedicated record type was added so the Voicemail page layout can be scoped to voicemail Cases
only (instead of overriding the layout for all Case types on a profile).

| Setting | Value |
|---|---|
| Record Type Name (API) | `Voicemail` |
| **Record Type Id** | **`012WA000001OMMzYAO`** |
| Business Process | `Voicemail_Process` (Status values: New (default), In Progress, Closed, Escalated, Critical, On Hold) |

> Case record types **require** a business process, so `Voicemail_Process` was created alongside.
> **Phase 2 impact:** the Python API must set `RecordTypeId` on create (see field mapping), and
> the integration user must have this record type assigned (granted via the permission set).

## Case Page Layout

Layout `Voicemail_Case_Layout` so agents see voicemail fields and can play the `.wav`.

| Section | Fields |
|---|---|
| Case Information | Subject, Status, Origin, OwnerId, CreatedDate **+ [AS-BUILT]** ContactId, Priority, Description, SuppliedName, SuppliedEmail, SuppliedPhone, SuppliedCompany |
| Voicemail Details | `Callback_Number__c`, `Caller_Name__c` |
| Related Lists | Files (ContentDocumentLinks) — **not** legacy Attachments |

> **[AS-BUILT] Required-field additions:** the org rejects a Case layout missing certain
> required fields, so ContactId, Priority, Description, and the Supplied* (Web-to-Case) fields
> were added, and Status is set to behavior **Required**. These are beyond the original
> Case Information field list but are mandatory for the layout to deploy.
>
> **[AS-BUILT] Lightning record page:** the page-layout Files related list and `.wav` playback
> are surfaced through the **Lightning record page** (App Builder), not the page layout alone:
> - A **Related Lists** (or Files) component must be on the page — the stock console page used
>   pinned single-related-list components that didn't include Files.
> - Native Salesforce file preview **cannot play audio** ("No preview available" for `.wav`).
>   In-browser playback is provided by a custom LWC (below).
>
> **[AS-BUILT] Layout assignment:** assign `Voicemail_Case_Layout` to the agent profile(s)
> **for the Voicemail record type only** — do not switch all record-type columns (that overrides
> their normal Case layout). Net change to non-voicemail Cases = none.

## Voicemail Audio Player (LWC) **[AS-BUILT — NEW]**

The requirement "playable in browser" is not achievable with Salesforce's native file viewer
(no audio preview). A custom Lightning Web Component provides inline playback.

| Component | Purpose |
|---|---|
| `voicemailAudioPlayer` (LWC) | HTML5 `<audio>` player; streams the latest `.wav` ContentVersion on the Case |
| `VoicemailAudioController` (Apex) | `@AuraEnabled` method returning the latest audio ContentVersion for the record |
| `VoicemailAudioControllerTest` | Apex test (2 methods, passing) so it is prod-deployable |

Placed on the Voicemail Lightning record page. Apex class access granted via the permission set.

## Deduplication Flow

| Setting | Value |
|---|---|
| Object | Case |
| Trigger | After save, insert only |
| Entry criteria | Origin = 'Phone' AND `Callback_Number__c` is not null |
| Logic | Query open Cases with same `Callback_Number__c` (Status != Closed, Id != triggering Id). If found, add a Case Comment to the triggering Case. Does not close or merge. |
| Flow name | `Education_Voicemail_Deduplicate_Check` |
| **[AS-BUILT] Comment body** | `"Possible duplicate — an open case already exists for this callback number. See Case " + {first matched CaseNumber}` (Cases have no `Name` field; `CaseNumber` is used). Flow is **Active** and confirmed firing in the UI. |

## Permission Set

| Setting | Value |
|---|---|
| Permission Set Name | `Education_Voicemail_Agent` |
| Label | Education Voicemail Agent |
| Case — Field Permissions | Read + Edit on `Callback_Number__c`, `Caller_Name__c` **+ [AS-BUILT]** `External_Id__c` |
| **[AS-BUILT] Record Type** | `Case.Voicemail` visible |
| **[AS-BUILT] Apex Class** | `VoicemailAudioController` enabled |

> **[AS-BUILT]** Deploy before assigning users. Assign to all Education agents **and** the Phase 2
> integration user (it grants the field access, record-type availability, and audio-player class).

## Expected Case Output (Phase 1 Validation) — CONFIRMED

| Salesforce Field | Value |
|---|---|
| Subject | Voicemail from Jane Doe — 803-555-1234 |
| Origin | Phone |
| Status | New |
| Queue | Education Voicemail |
| Record Type **[AS-BUILT]** | Voicemail |
| `Callback_Number__c` | 8035551234 |
| `Caller_Name__c` | Jane Doe |
| Files | Manually uploaded `.wav`, played inline via the audio-player LWC (download also works) |

---

# Phase 2 — Python API + MuleSoft Requirements

Phase 2 begins only after all Phase 1 items are deployed and validated **and** the external
prerequisites are confirmed.

## Python API

The Python API (FastAPI on Azure) is the only service that talks to Salesforce.

**Endpoints:** `POST /api/voicemail` · `POST /api/voicemail/{case_id}/attachment` ·
`GET /api/cases` · `GET /api/cases/{id}`

### Case field mapping (POST /api/voicemail)

| Salesforce Field | Value / Source |
|---|---|
| Subject | "Voicemail from {caller_name} — {caller_phone}" |
| Origin | Phone (hardcoded) |
| Status | New (hardcoded) |
| OwnerId | Education Voicemail Queue ID (`00GWA000007oHmP2AU`) from env |
| **RecordTypeId [AS-BUILT — NEW]** | **`012WA000001OMMzYAO`** (Voicemail) from env — required so the Case gets the Voicemail layout. Integration user must have the record type (via perm set). |
| `Callback_Number__c` | caller_phone |
| `Caller_Name__c` | caller_name |
| `External_Id__c` | Idempotency key from MuleSoft |
| Description | (blank — reserved for transcription) |

**Idempotency:** query `Case WHERE External_Id__c = {external_id}` first; if found, return the
existing Case Id with `duplicate: true`.

**File attachment:** ContentVersion + ContentDocumentLink (not legacy Attachment). No `.wav` →
create the Case anyway and log a warning; do not fail.

**Auth:** MuleSoft → Python API via shared `X-API-Key`. Python API → Salesforce via OAuth 2.0
client credentials (Connected App).

## MuleSoft Flow

IMAP listener (**Office 365 / IMAP Email Listener**) on **`estfvoicemail@ed.sc.gov`** → parse subject (regex `\d{10}`, split on " - ") →
extract `.wav` → POST `/api/voicemail` → POST attachment → error handler (admin alert + Anypoint log).

---

## Prerequisites by Phase

### Phase 1 (Salesforce admin) — COMPLETE
- `Callback_Number__c`, `Caller_Name__c`, `External_Id__c` on Case ✅
- Education Voicemail queue + Queue ID ✅
- Voicemail record type + business process ✅ **[AS-BUILT]**
- `Education_Voicemail_Agent` permission set deployed ✅ (assign to full Education team — pending)
- `Voicemail_Case_Layout` deployed ✅ (assign per profile for the Voicemail record type — pending)
- Audio-player LWC ✅ **[AS-BUILT]** (place on record page — manual)

### Phase 2 (must be complete before Python/MuleSoft build)
- All Phase 1 items confirmed (Queue ID + field API names + **Record Type Id**) — in hand
- Mailbox **`estfvoicemail@ed.sc.gov`** IMAP access (Office 365 / IMAP) — service account / app password from M365 admin ☐
- Salesforce Connected App (OAuth) client ID + secret — SF admin ☐
- Anypoint Platform access — MuleSoft admin ☐
- Python API hosting (Azure) — Azure admin ☐
- Shared API key — dev team ☐

## Out of Scope (both phases)
Audio transcription · auto case assignment to a specific agent · email deletion/archiving ·
Experience Cloud / self-service portal.

## Future Phase — Transcription
Azure AI Speech transcription inserted between MuleSoft Step 3 and Step 4; transcript stored in
Case `Description`. No Salesforce data-model changes anticipated.
