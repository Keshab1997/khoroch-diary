# Play Console Data safety — working draft

> **Do not submit these answers verbatim.** Google assigns the developer responsibility for accuracy. This is a code-informed checklist, not a completed declaration; verify every SDK, Play Console wording, and production configuration first.

## Observed app behavior
- Offline ledger is stored in local SQLite; no account is needed for core use.
- Optional Google OAuth/Supabase Auth is used for cloud backup/sync.
- If the user opts into cloud sync, the app sends khata records and transaction records to the configured Supabase project.
- Manual JSON backup is user-initiated and unencrypted; it stays in a user-chosen file location unless the user shares it.
- Local profile name and photo, custom categories, and cash note-counter data are stored locally; local backup format v2 can include these. Profile name/photo are not part of the current cloud-sync schema.
- Local source includes a confirmed in-app cloud-account deletion action and authenticated Supabase Edge Function client; the Edge Function is deployed. Only the unauthenticated 401 response has been safely verified; no real account deletion or authenticated destructive test has been run. Sign-out remains separate and does not delete data.
- No ads or analytics feature was found in the app source/dependency list, but verify the final AAB and all bundled SDKs.

## Data types to assess in the Play Console form

| Potential Play data type | Why it may apply | Collection / purpose notes |
|---|---|---|
| Personal info — Email address | Google account email is mapped into the cloud user model | Only for optional sign-in/cloud account; account management and sync |
| Personal info — User IDs | Supabase Auth user UUID and app record identifiers | Account association, ownership, and sync |
| Financial info — Other financial info / financial records (use the exact current Console category) | Khata opening balances and income/expense amounts | Only sent to Supabase after opt-in sync; core local use remains on-device |
| App activity / Other user-generated content (if applicable in current form) | User-entered descriptions, category names, custom categories, and note-counter data | Local by default; some ledger rows/description fields sync when enabled |
| Photos and videos (review carefully) | Optional local profile avatar | Stored locally, and can be included in a user-created JSON backup; not sent in cloud sync. Confirm whether any selected-data transfer in the backup flow is in scope for the form |

Do not claim that local-only data is collected by the developer if it never leaves the device; do separately disclose data that is transmitted to Google/Supabase when the user enables those features. Google's definitions and exceptions for user-initiated transfers/service providers can affect the exact answers.

## Draft answers to verify
- **Does the app collect or share data?** The optional cloud feature transmits account and ledger data to Google/Supabase. Confirm the current form's treatment of service providers and user-initiated sync.
- **Is collection optional?** Cloud account data and cloud ledger sync are optional; user must choose Google sign-in and confirm sync. The local ledger works without it.
- **Is data encrypted in transit?** Yes for Google/Supabase requests over HTTPS. Do not claim end-to-end encryption.
- **Is data encrypted at rest?** Do not answer yes for the app's local database or exported JSON. Confirm the Supabase project's provider-side storage statement separately.
- **Can users request deletion?** The app source has an in-app confirmed cloud deletion path, the authenticated backend is deployed, and a public deletion page with an email request path is drafted. Public hosting and a safe end-to-end verification are still pending before this can be declared in Play Console.
- **Ads / analytics:** No ad or analytics feature found in current source; audit release dependencies and SDK behavior before selecting answers.
- **Data shared with third parties:** assess Google as authentication provider and Supabase as cloud processor against the live Console definitions. Disclose both consistently in the policy.

## Required completion work
1. Deploy and verify the in-app account-deletion implementation and authenticated Supabase Edge Function; do not confuse sign-out or tombstones with deletion.
2. Host and verify the public deletion-request webpage, and enter it in the Data safety deletion questions.
3. Host and verify the public privacy-policy URL and in-app policy links.
4. Confirm Supabase region (`ap-northeast-2`), provider retention/logging configuration, processors, and deletion behavior.
5. Review the final AAB's transitive SDK list and all Android permissions; revise the form/policy for any SDK collection.
6. Submit and maintain the form in Play Console; re-review after material data-handling changes.

Official Google guidance: [Data safety](https://support.google.com/googleplay/android-developer/answer/10787469), [User Data & privacy policy](https://support.google.com/googleplay/android-developer/answer/10144311), [account deletion](https://support.google.com/googleplay/android-developer/answer/13327111).
