# Khoroch Diary — Play release checklist

> **Status: NOT READY TO SUBMIT.** Publisher/contact details and local deletion-flow code are now in place, but public deployment, end-to-end verification, legal review, final SDK/data audit, and store assets remain. Do not submit an app build or claim policy compliance until every blocking item below is completed.

## Blocking privacy / account items
- [x] Publisher confirmed as **Keshab Studios · India**; support/privacy email supplied: `keshabsarkar2018@gmail.com`.
- [x] Supabase project region confirmed: `ap-northeast-2` (Seoul, South Korea); current app sync sends account email/ID and ledger mirror fields as described in the draft.
- [x] In-app permanent cloud account deletion is implemented locally; the authenticated Supabase Edge Function is deployed. An unauthenticated request was safely verified to return 401; no real account deletion or authenticated destructive test has been run.
- [x] External deletion page source now explains in-app deletion and provides an email request path; the support process has no fixed completion-time promise. **Page is not hosted/verified yet.**
- [ ] Deploy and safely verify the Edge Function. Do not use real user accounts or run destructive production tests; confirm database FK cascade behavior and failure handling.
- [ ] Publish the app-specific policy and deletion resources on stable HTTPS, publicly accessible worldwide, no login/no PDF; verify links both in-app and in Play Console.
- [ ] Obtain legal review of the privacy policy and Terms of Use. Terms draft selects India governing law but leaves venue for counsel; this is not legal advice.
- [ ] Complete the Play Console Data safety form from the final release AAB/SDK inventory, including account email/user ID and optional cloud-synced ledger data as applicable.
- [ ] Verify no unintended retention claims; deleted account/ledger data is removed from active Supabase records, while provider operational logs/backups may follow provider retention.


## Store assets and listing
- [x] App icon: `store/assets/app-icon-512.png`, 512×512 RGBA PNG, about 325 KB; Android mipmap launcher icons replaced.
- [ ] Feature graphic: create the required 1024×500 JPEG or 24-bit PNG (no alpha).
- [ ] Add current, truthful screenshots. Current local design-preview captures use an unwired profile/settings state; do not upload them as final production screenshots. Google currently requires store preview assets; check the live Console's device-specific screenshot requirements.
- [ ] Review English and Bengali listing copy in `PLAY_STORE_LISTING.md`; ensure every advertised feature is present in the release.
- [x] Support email and planned public URLs are entered in `PLAY_STORE_LISTING.md`; verify they resolve publicly before using in Play Console.

## Play Console declarations / release gates
- [ ] Complete App access instructions (explain that basic use works offline; cloud sync uses optional Google sign-in).
- [ ] Complete target audience and content-rating (IARC) questionnaires; accurately answer whether the app is child-directed.
- [ ] Complete the Financial features declaration. This is a personal ledger, not a bank/lender/payment/investment service; review the current choices and do not select “no financial features” without checking whether “other/personal finance tracking” applies.
- [ ] Complete the Ads declaration; source contains no ads integration, but verify the final AAB/dependencies.
- [ ] New app submissions and updates must target **Android 16 / API 36 or higher from 31 August 2026**. This project inherits `targetSdk` from Flutter; verify the built AAB resolves to API 36 or higher before upload.
- [ ] Confirm Play App Signing / upload key configuration and upload the CI-signed AAB. Never commit signing files or secrets.
- [ ] Finish any testing-track/account-verification requirements shown in this developer's Play Console.
- [ ] Only after all checks: Keshab reviews and submits the release in Play Console. Nothing in this task has been published or uploaded.

## Prepared files
- `PRIVACY_POLICY.md` — bilingual draft, now filled with supplied publisher/contact and verified Supabase region; legal review and final SDK audit remain.
- `TERMS_OF_USE.md` — bilingual draft for Indian legal review; court venue still requires counsel.
- `DATA_SAFETY_DRAFT.md` — code-informed answers to verify, not a submitted declaration.
- `IN_APP_CLOUD_DISCLOSURE.md` — bilingual disclosure copy to check against the consent flow.
- `PLAY_STORE_LISTING.md` — bilingual listing copy with supplied contact and planned URLs; verify after hosting.
- `site/privacy-policy.html` / `site/terms-of-use.html` — self-contained draft pages; not published.
- `site/account-deletion.html` — bilingual deletion instructions and email request pathway; deploy and verify, then confirm support inbox operations.
- `assets/app-icon-512.png` — Play listing icon; Android launcher mipmaps use the same selected design.

## Official references
- [Google Play User Data / privacy policy](https://support.google.com/googleplay/android-developer/answer/10144311)
- [Data safety form](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111)
- [Store listing preview assets](https://support.google.com/googleplay/android-developer/answer/9866151)
- [Target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878)
- [Financial features declaration](https://support.google.com/googleplay/android-developer/answer/13849271)
