# Khoroch Diary — Privacy Policy

> **DRAFT FOR REVIEW — NOT THE FINAL EFFECTIVE POLICY.** Publisher and support contact are filled in; the policy still requires legal review and a release-level data/SDK audit. The deletion feature and public deletion page must be deployed and verified before this draft is published. Effective date is the publication date.

- **App:** Khoroch Diary
- **Android package:** `com.keshabstudios.khorochdiary`
- **Developer/publisher:** `Keshab Studios`
- **Privacy contact:** `keshabsarkar2018@gmail.com`
- **Effective date:** `Draft prepared 23 November 2026; not effective until approved publication`
- **Public policy URL:** `https://keshab1997.github.io/khoroch-diary/privacy-policy.html`

## English

### 1. About this policy
Khoroch Diary is an offline-first personal ledger for recording income, expenses, and balances. Core ledger use does not require an account or an internet connection. This policy covers the Android app and its optional Google sign-in and cloud backup/sync features.

### 2. Information stored on your device
The app stores ledger information in a local SQLite database, including khata names and balances, income/expense amounts, categories, descriptions, dates, and locally generated record IDs. It also stores custom categories, note-counter sessions, and an optional local profile name and photo. The app does not send the local profile name or photo as part of cloud sync.

Local data remains on the device until you clear the app's data or uninstall it, subject to Android device backup/transfer settings. The app itself does not encrypt its local SQLite database.

### 3. Optional sign-in and cloud sync
If you choose Google sign-in and affirmatively confirm cloud sync, the app uses Google OAuth through Supabase Auth. Supabase processes the account email and account/user identifier needed for authentication. The app can sync khata records and transaction records to the Khoroch Diary Supabase project. Synced fields include khata names, opening balances, currency, ordering, transaction type, amount, category ID, optional description, date, record IDs, and create/update/delete timestamps. Cloud sync is optional; it is not needed for the local ledger.

Synced records are associated with your authenticated account. Row-level security is enabled so ordinary authenticated requests are limited to that account's rows. Network traffic to Google and Supabase uses HTTPS. Supabase hosts the cloud service in the project region configured by the developer: `ap-northeast-2 (Seoul, South Korea)`. Google and Supabase may process technical request, authentication, and security information under their own policies.

The app does not sell ledger data or use it for advertising. The current source does not include an advertising or analytics feature; verify the final release's complete SDK/dependency inventory before making this statement publicly.

### 4. Backups and files you choose
The app's manual offline backup is a user-initiated JSON file. It may contain ledger records, the local profile name/photo, custom categories, and note-counter data. The backup file is **not encrypted by the app**. It is saved or selected using the platform's file picker; after export, its location and any onward sharing are controlled by you and the apps/storage providers you choose. Keep backup files private and secure.

### 5. Information sharing
We do not sell your personal information. Data is sent to:

- **Google**, when you choose Google sign-in, to authenticate your selected account.
- **Supabase**, only when you opt into cloud sign-in/sync, to authenticate the account and host/synchronize its khata and transaction records.
- **Your chosen file/storage provider**, if you export, import, move, or share a backup file yourself.

The developer may administer the Supabase project for service operation, security, and support. No other third-party advertising or analytics service is intentionally integrated in the current source tree; this must be rechecked against the final release bundle.

### 6. Security
Cloud requests use HTTPS and the database uses account-scoped row-level security for normal client access. The app does not provide end-to-end encryption and does not encrypt the local SQLite database or exported JSON backup. Protect your device, Google account, and backup files. No method of storage or transmission can be guaranteed completely secure.

### 7. Retention, deletion, and sign-out
Signing out clears the local authentication session; it does **not** delete the account or cloud data. To permanently delete your Khoroch Diary cloud account, use **Profile → Cloud Backup → Delete cloud account** in the app, or follow the external deletion instructions at https://keshab1997.github.io/khoroch-diary/account-deletion.html. Account deletion removes the Supabase authentication account and its synced khata/transaction records. It does not delete the local ledger on this device; clear app data or uninstall the app to remove that copy. Exported JSON backups must be deleted separately by you.

If you cannot access the app, email keshabsarkar2018@gmail.com from the email address associated with your Google sign-in and request deletion. Never send a password or backup file. There is no fixed completion-time promise. We do not intentionally retain a copy of deleted account or ledger data; limited security logs or provider backups may persist for the service providers’ operational retention periods.

### 8. Children and changes
The Play Console target-audience declaration must be completed by the developer. Do not describe the app as child-directed unless it is intentionally designed and compliant for children. If data practices change, update this policy, the in-app disclosure, and the Play Console Data safety answers before releasing the change.

### 9. Contact
For privacy questions or requests: **keshabsarkar2018@gmail.com**. Include “Khoroch Diary privacy” in the subject. Do not send passwords or backup files by email.

---

## বাংলা

### ১. এই নীতির বিষয়ে
Khoroch Diary ব্যক্তিগত আয়, খরচ ও ব্যালেন্সের হিসাব রাখার অফলাইন-প্রথম অ্যাপ। মূল খাতা ব্যবহার করতে অ্যাকাউন্ট বা ইন্টারনেট লাগে না। এই নীতি Android অ্যাপ এবং ঐচ্ছিক Google সাইন-ইন ও ক্লাউড ব্যাকআপ/সিঙ্কের ক্ষেত্রে প্রযোজ্য।

### ২. ডিভাইসে সংরক্ষিত তথ্য
অ্যাপটি ডিভাইসের SQLite ডেটাবেসে খাতার নাম ও ব্যালেন্স, আয়/ব্যয়ের অঙ্ক, বিভাগ, বিবরণ, তারিখ এবং অ্যাপের তৈরি রেকর্ড আইডি রাখে। কাস্টম বিভাগ, নোট-কাউন্টারের সেশন এবং চাইলে স্থানীয় প্রোফাইলের নাম ও ছবি-ও রাখা হয়। স্থানীয় প্রোফাইলের নাম বা ছবি ক্লাউড সিঙ্কে পাঠানো হয় না।

অ্যাপের ডেটা মুছে ফেলা বা অ্যাপ আনইনস্টল করা পর্যন্ত স্থানীয় তথ্য ডিভাইসে থাকে; Android-এর ডিভাইস ব্যাকআপ/ট্রান্সফার সেটিংস প্রযোজ্য হতে পারে। অ্যাপটি নিজে স্থানীয় SQLite ডেটাবেস এনক্রিপ্ট করে না।

### ৩. ঐচ্ছিক সাইন-ইন ও ক্লাউড সিঙ্ক
আপনি Google দিয়ে সাইন-ইন করে ক্লাউড সিঙ্কে সম্মতি দিলে, Supabase Auth-এর মাধ্যমে Google OAuth ব্যবহৃত হয়। সাইন-ইনের জন্য Supabase আপনার অ্যাকাউন্টের ইমেল ও অ্যাকাউন্ট/ইউজার আইডি প্রক্রিয়া করে। অ্যাপটি খাতার তথ্য ও লেনদেন Khoroch Diary-এর Supabase প্রকল্পে সিঙ্ক করতে পারে। সিঙ্কে খাতার নাম, প্রারম্ভিক ব্যালেন্স, মুদ্রা, সাজানোর ক্রম, লেনদেনের ধরন, অঙ্ক, বিভাগ আইডি, ঐচ্ছিক বিবরণ, তারিখ, রেকর্ড আইডি এবং তৈরি/পরিবর্তন/মুছে-ফেলার সময় অন্তর্ভুক্ত থাকে। ক্লাউড সিঙ্ক ঐচ্ছিক; স্থানীয় খাতা চালাতে এর প্রয়োজন নেই।

সিঙ্ক করা তথ্য আপনার সাইন-ইন করা অ্যাকাউন্টের সঙ্গে যুক্ত থাকে। সাধারণ অ্যাপ-অনুরোধে row-level security ব্যবহারকারীর নিজের রেকর্ডেই প্রবেশ সীমিত করে। Google ও Supabase-এ নেটওয়ার্ক যোগাযোগ HTTPS দিয়ে হয়। Supabase প্রকল্পের অঞ্চল: `ap-northeast-2 (সিউল, দক্ষিণ কোরিয়া)`। Google ও Supabase তাদের নিজস্ব নীতি অনুযায়ী সাইন-ইন, নিরাপত্তা ও প্রযুক্তিগত অনুরোধ-সংক্রান্ত তথ্য প্রক্রিয়া করতে পারে।

অ্যাপটি হিসাবের তথ্য বিক্রি করে না বা বিজ্ঞাপনের জন্য ব্যবহার করে না। বর্তমান সোর্সে বিজ্ঞাপন বা অ্যানালিটিক্স ফিচার নেই; প্রকাশের আগে সম্পূর্ণ SDK/নির্ভরতার তালিকা আবার যাচাই করতে হবে।

### ৪. ব্যাকআপ ও আপনার বেছে নেওয়া ফাইল
অ্যাপের অফলাইন ব্যাকআপ ব্যবহারকারীর অনুরোধে তৈরি JSON ফাইল। এতে খাতার তথ্য, স্থানীয় প্রোফাইলের নাম/ছবি, কাস্টম বিভাগ এবং নোট-কাউন্টারের তথ্য থাকতে পারে। অ্যাপ এই ব্যাকআপ ফাইল **এনক্রিপ্ট করে না**। প্ল্যাটফর্মের ফাইল-পিকার দিয়ে ফাইল সংরক্ষণ বা বেছে নেওয়া হয়। রপ্তানির পর ফাইলের অবস্থান ও অন্য কোথাও পাঠানো আপনার এবং আপনার বেছে নেওয়া অ্যাপ/স্টোরেজ পরিষেবার নিয়ন্ত্রণে। ব্যাকআপ ব্যক্তিগত ও নিরাপদ স্থানে রাখুন।

### ৫. তথ্য কার সঙ্গে ভাগ হয়
আমরা ব্যক্তিগত তথ্য বিক্রি করি না। তথ্য পাঠানো হয়:

- **Google-এ**, আপনি Google সাইন-ইন বেছে নিলে, নির্বাচিত অ্যাকাউন্ট যাচাই করতে।
- **Supabase-এ**, আপনি ঐচ্ছিক ক্লাউড সাইন-ইন/সিঙ্ক চালু করলেই, অ্যাকাউন্ট যাচাই এবং খাতা/লেনদেন হোস্ট ও সিঙ্ক করতে।
- **আপনার বেছে নেওয়া ফাইল/স্টোরেজ পরিষেবায়**, আপনি নিজে ব্যাকআপ রপ্তানি, আমদানি, সরানো বা শেয়ার করলে।

পরিষেবা চালানো, নিরাপত্তা ও সহায়তার জন্য ডেভেলপার Supabase প্রকল্প পরিচালনা করতে পারেন। বর্তমান সোর্সে অন্য কোনো বিজ্ঞাপন বা অ্যানালিটিক্স পরিষেবা ইচ্ছাকৃতভাবে যুক্ত নেই; প্রকাশিত bundle-এ আবার পরীক্ষা করতে হবে।

### ৬. নিরাপত্তা
ক্লাউড অনুরোধ HTTPS ব্যবহার করে এবং সাধারণ অ্যাপ-অ্যাক্সেসের জন্য ডেটাবেসে অ্যাকাউন্টভিত্তিক row-level security আছে। অ্যাপে end-to-end encryption নেই; স্থানীয় SQLite ডেটাবেস বা রপ্তানি করা JSON ব্যাকআপ এনক্রিপ্ট করা হয় না। নিজের ডিভাইস, Google অ্যাকাউন্ট ও ব্যাকআপ ফাইল সুরক্ষিত রাখুন। কোনো স্টোরেজ বা যোগাযোগ পদ্ধতিই শতভাগ নিরাপদ বলে নিশ্চয়তা দেওয়া যায় না।

### ৭. তথ্য রাখা, মুছে ফেলা ও সাইন-আউট
সাইন-আউট করলে ডিভাইসের লগইন সেশন পরিষ্কার হয়; অ্যাকাউন্ট বা ক্লাউড তথ্য মুছে যায় না। Khoroch Diary ক্লাউড অ্যাকাউন্ট স্থায়ীভাবে মুছতে অ্যাপে **Profile → Cloud Backup → Delete cloud account** ব্যবহার করুন, অথবা https://keshab1997.github.io/khoroch-diary/account-deletion.html পেজের নির্দেশনা অনুসরণ করুন। অ্যাকাউন্ট মুছলে Supabase authentication account এবং তার সিঙ্ক করা খাতা/লেনদেন মুছে যায়। এই ফোনের স্থানীয় খাতার কপি মুছে যায় না; সেটি সরাতে অ্যাপের তথ্য মুছুন বা অ্যাপ আনইনস্টল করুন। রপ্তানি করা JSON ব্যাকআপ আপনাকে আলাদাভাবে মুছতে হবে।

অ্যাপে প্রবেশ করতে না পারলে Google সাইন-ইনে ব্যবহৃত ইমেল ঠিকানা থেকে keshabsarkar2018@gmail.com-এ মুছে ফেলার অনুরোধ পাঠান। পাসওয়ার্ড বা ব্যাকআপ ফাইল পাঠাবেন না। নির্দিষ্ট পূরণ-সময়সীমার প্রতিশ্রুতি নেই। মুছে ফেলা অ্যাকাউন্ট বা হিসাবের কপি আমরা ইচ্ছাকৃতভাবে রাখি না; পরিষেবা প্রদানকারীর পরিচালনাগত retention সময়ে সীমিত নিরাপত্তা লগ বা ব্যাকআপ থাকতে পারে।

### ৮. শিশু ও নীতির পরিবর্তন
Play Console-এ লক্ষ্য বয়সের ঘোষণা ডেভেলপারকে পূরণ করতে হবে। শিশুদের জন্য বিশেষভাবে তৈরি না হলে অ্যাপটিকে শিশুদের জন্য বলে প্রচার করবেন না। তথ্য ব্যবহারের ধরন বদলালে নীতি, অ্যাপের ভেতরের ঘোষণা এবং Play Console Data safety উত্তর রিলিজের আগে আপডেট করুন।

### ৯. যোগাযোগ
গোপনীয়তা-সংক্রান্ত প্রশ্ন বা অনুরোধ: **keshabsarkar2018@gmail.com**। ইমেলের subject-এ “Khoroch Diary privacy” লিখুন। ইমেলে পাসওয়ার্ড বা ব্যাকআপ ফাইল পাঠাবেন না।

---

## Before publication
1. Obtain legal review and verify every data/SDK disclosure against the release bundle.
2. Deploy and end-to-end test account deletion and the external deletion instructions.
3. Publish this policy at a stable public HTTPS webpage with no login/geofence and verify the in-app and Play Console links.
4. Set the effective date when the approved page is published.
