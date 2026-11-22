# In-app cloud-sync disclosure — review against the final flow

> The current sign-in page explains that cloud backup is optional and local khatas stay on the phone. Use this copy as a policy-review checklist; confirm it is shown before the first cloud transfer and that Google sign-in + the explicit Sync action is affirmative consent. A privacy policy alone is not a substitute for prominent disclosure where required.

## English

**Optional cloud backup and sync**

Your khata works offline and stays on this device unless you choose cloud sync. If you continue with Google and confirm Sync, Khoroch Diary sends your Google account email/user ID and the khata and transaction records on this device (including names, balances, amounts, categories, dates, and any descriptions) to the Khoroch Diary Supabase service so you can back up and sync across devices. The profile photo, custom categories, and note-counter sessions are not included in cloud sync. Data is sent over HTTPS. You can choose “Not now” and keep using the local ledger.

**Before launch:** the in-app Privacy Policy and deletion links have been added in the sign-in flow, and the local source includes a confirmed account-deletion action. The authenticated Supabase deletion function is deployed; public pages are not yet hosted and authenticated destructive behavior has not been tested. Confirm the provider/region and retention statements against production before launch.

## বাংলা

**ঐচ্ছিক ক্লাউড ব্যাকআপ ও সিঙ্ক**

আপনার খাতা অফলাইনে চলে এবং আপনি ক্লাউড সিঙ্ক না বেছে নিলে তথ্য এই ডিভাইসেই থাকে। Google দিয়ে এগিয়ে গিয়ে সিঙ্ক নিশ্চিত করলে, Khoroch Diary আপনার Google অ্যাকাউন্টের ইমেল/ইউজার আইডি এবং এই ডিভাইসের খাতা ও লেনদেনের তথ্য (নাম, ব্যালেন্স, অঙ্ক, বিভাগ, তারিখ ও দেওয়া বিবরণসহ) Khoroch Diary-এর Supabase পরিষেবায় পাঠায়, যাতে অন্য ডিভাইসে ব্যাকআপ ও সিঙ্ক করা যায়। প্রোফাইল ছবি, কাস্টম বিভাগ ও নোট-কাউন্টারের সেশন ক্লাউড সিঙ্কে যায় না। তথ্য HTTPS দিয়ে পাঠানো হয়। “এখন নয়” বেছে নিয়ে স্থানীয় খাতা ব্যবহার করতে পারবেন।

**প্রকাশের আগে:** এখানে সহজে দেখা যায় এমন Privacy Policy লিংক দিন; প্রকৃত পরিষেবা/অঞ্চল ও তথ্য রাখার সময় লিখুন; অ্যাপের ভেতরে অ্যাকাউন্ট মুছে ফেলার ব্যবস্থা যোগ করুন। স্থায়ী মুছে ফেলার প্রক্রিয়া তৈরি ও পরীক্ষা না করে ক্লাউড তথ্য মুছে ফেলার দাবি করবেন না।
