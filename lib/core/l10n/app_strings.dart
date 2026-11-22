import '../format/date_format.dart';
import '../format/money.dart';

/// Supported UI languages. Endonyms stay recognizable even after switching.
enum AppLanguage {
  en('English'),
  bn('বাংলা');

  const AppLanguage(this.endonym);

  final String endonym;

  /// Accepts a language code or locale tag, such as bn-IN. Defaults to English.
  static AppLanguage fromCode(String? code) {
    final String? language = code
        ?.trim()
        .toLowerCase()
        .split(RegExp('[-_]'))
        .first;
    return language == 'bn' ? bn : en;
  }
}

/// UI copy only. Never use localized labels as category IDs or stored values.
/// Each key must supply both translations at compile time.
enum AppString {
  // Home and shared navigation
  home('Home', 'মূল পাতা'),
  appName('Khoroch Diary', 'খরচের ডায়েরি'),
  tagline('Plan · Track · Save', 'পরিকল্পনা · হিসাব · সঞ্চয়'),
  personalKhata('Personal Khata', 'ব্যক্তিগত খাতা'),
  activeKhata('Active Khata', 'সক্রিয় খাতা'),
  tapToSwitch('Tap to switch', 'বদলাতে চাপুন'),
  recentTransactions('Recent Transactions', 'সাম্প্রতিক লেনদেন'),
  addNewEntry('Add New Entry', 'নতুন লেনদেন যোগ করুন'),
  homePreview(
    'Sample ledger · preview data only',
    'নমুনা খাতা · শুধু প্রিভিউয়ের তথ্য',
  ),
  onboardingOneTitle(
    'Your everyday khata, made simple',
    'প্রতিদিনের হিসাব, সহজে',
  ),
  onboardingOneBody(
    'Record income and expenses, then see your balance and recent activity in one place.',
    'আয়-ব্যয় লিখুন, ব্যালেন্স ও সাম্প্রতিক লেনদেন এক জায়গায় দেখুন।',
  ),
  onboardingTwoTitle(
    'Works offline. No account needed.',
    'অফলাইনেই চলে, অ্যাকাউন্ট লাগে না',
  ),
  onboardingTwoBody(
    'Your core ledger stays on this device. Add and review entries even without internet.',
    'মূল হিসাব এই ডিভাইসেই থাকে। ইন্টারনেট ছাড়াই লেনদেন যোগ করুন ও দেখুন।',
  ),
  onboardingThreeTitle(
    'Keep different khatas organized',
    'আলাদা খাতা, গুছানো হিসাব',
  ),
  onboardingThreeBody(
    'Create separate khatas and keep income, expenses, and remaining balances clear.',
    'আলাদা খাতা তৈরি করুন; আয়, ব্যয় ও অবশিষ্ট টাকার হিসাব পরিষ্কার রাখুন।',
  ),
  onboardingFourTitle(
    'Useful tools. Backup on your terms.',
    'দরকারি টুল, ব্যাকআপ আপনার পছন্দে',
  ),
  onboardingFourBody(
    'Use the calculator and cash note counter. Export a backup or choose optional Google cloud sync when you want.',
    'ক্যালকুলেটর ও নগদ নোট কাউন্টার ব্যবহার করুন। চাইলে ব্যাকআপ নিন বা ঐচ্ছিক Google ক্লাউড সিঙ্ক চালু করুন।',
  ),
  onboardingSkip('Skip', 'এড়িয়ে যান'),
  onboardingNext('Next', 'পরবর্তী'),
  onboardingBack('Back', 'ফিরে যান'),
  onboardingStart(
    'Start using Khoroch Diary',
    'Khoroch Diary ব্যবহার শুরু করুন',
  ),
  onboardingLanguage('Bengali', 'English-এ যান'),
  settings('Settings', 'সেটিংস'),
  totalIncome('Total Income', 'মোট আয়'),
  totalExpense('Total Expense', 'মোট ব্যয়'),
  remainingBalance('Remaining Balance', 'অবশিষ্ট টাকা'),
  homeEmpty(
    'No transactions yet. Add an entry to see it here.',
    'এখনও কোনো লেনদেন নেই। লেনদেন যোগ করলে এখানে দেখা যাবে।',
  ),
  viewAll('View All', 'সব দেখুন'),
  openLedgerFailed(
    'Could not open local ledger.',
    'ডিভাইসের খাতা খোলা যায়নি।',
  ),
  webLedgerUnavailable(
    'Web preview only: offline storage is not available here yet.',
    'শুধু ওয়েব প্রিভিউ: এখানে এখনও অফলাইনে তথ্য রাখার সুবিধা নেই।',
  ),

  groceryShopping('Grocery Shopping', 'মুদির বাজার'),
  lunchWithFriends('Lunch with Friends', 'বন্ধুদের সঙ্গে দুপুরের খাবার'),
  mobileRecharge('Mobile Recharge', 'মোবাইল রিচার্জ'),
  giftForMom('Gift for Mom', 'মায়ের জন্য উপহার'),
  busFare('Bus Fare', 'বাসভাড়া'),
  teaWithTeam('Tea with Team', 'সহকর্মীদের সঙ্গে চা'),

  // Entry and editor
  addEntry('Add Entry', 'লেনদেন যোগ করুন'),
  save('Save', 'সংরক্ষণ করুন'),
  amount('Amount', 'টাকার পরিমাণ'),
  date('Date', 'তারিখ'),
  futureDate('This date is in the future.', 'এই তারিখটি ভবিষ্যতের।'),
  category('Category', 'বিভাগ'),
  pickCategory('Pick a category', 'একটি বিভাগ বেছে নিন'),
  description('Description', 'বিবরণ'),
  saveEntry('Save Entry', 'লেনদেন সংরক্ষণ করুন'),
  income('Income', 'আয়'),
  expense('Expense', 'ব্যয়'),
  shopping('Shopping', 'কেনাকাটা'),
  food('Food', 'খাবার'),
  travel('Travel', 'যাতায়াত'),
  bills('Bills', 'বিল'),
  gifts('Gifts', 'উপহার'),
  validAmount('Enter a valid amount', 'সঠিক টাকার পরিমাণ লিখুন'),
  categoryIncome('Category: Income', 'বিভাগ: আয়'),
  descriptionHint('What was it for?', 'কী বাবদ লেনদেন?'),
  descriptionLimit('Up to 120 characters', 'সর্বোচ্চ ১২০ অক্ষর'),
  descriptionOptional(
    'Up to 120 characters, optional',
    'সর্বোচ্চ ১২০ অক্ষর, ঐচ্ছিক',
  ),
  descriptionTooLong(
    'Description must be 120 characters or fewer',
    'বিবরণ ১২০ অক্ষরের বেশি হতে পারবে না',
  ),
  notebookIllustration(
    'Open ledger notebook and pen',
    'খোলা হিসাবের খাতা ও কলম',
  ),
  everyExpenseCounts('Every expense counts…', 'প্রতিটি খরচের হিসাব রাখুন…'),
  oneEntryAtATime(
    'A clearer picture starts with one entry.',
    'একটি লেনদেনেই হিসাব আরও পরিষ্কার হয়।',
  ),
  updating('Updating…', 'পরিবর্তন করা হচ্ছে…'),
  deleting('Deleting…', 'মুছে ফেলা হচ্ছে…'),
  editSaveFailed(
    'Could not save your changes. You can try again.',
    'পরিবর্তন সংরক্ষণ করা যায়নি। আবার চেষ্টা করতে পারেন।',
  ),
  localSaveFailed(
    'Could not save locally. Please try again.',
    'ডিভাইসে সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।',
  ),
  deleteFailed(
    'Could not delete this transaction. It has not been removed, so you can try again.',
    'লেনদেনটি মোছা যায়নি। এটি এখনও আছে, আবার চেষ্টা করতে পারেন।',
  ),
  deleteQuestion('Delete this transaction?', 'এই লেনদেনটি মুছে ফেলবেন?'),
  deleteExplanation(
    'It will be removed from this khata on this device.',
    'এই ডিভাইসের খাতা থেকে লেনদেনটি সরানো হবে।',
  ),
  cancel('Cancel', 'বাতিল করুন'),
  delete('Delete', 'মুছে ফেলুন'),
  editTransaction('Edit Transaction', 'লেনদেন সম্পাদনা করুন'),
  updateTransaction('Update transaction', 'লেনদেনের পরিবর্তন সংরক্ষণ করুন'),
  deleteTransaction('Delete transaction', 'লেনদেন মুছে ফেলুন'),
  amountPrecision(
    'Enter an amount with up to 9 digits and 2 decimals',
    'দশমিকের আগে সর্বোচ্চ ৯টি ও পরে ২টি অঙ্ক লিখুন',
  ),
  positiveAmount(
    'Amount must be more than zero',
    'টাকার পরিমাণ শূন্যের বেশি হতে হবে',
  ),

  // Khata switching and management
  chooseKhata('Choose Khata', 'খাতা বেছে নিন'),
  newKhata('New Khata', 'নতুন খাতা'),
  manageKhatas('Manage Khatas', 'খাতা পরিচালনা করুন'),
  khataName('Khata name', 'খাতার নাম'),
  create('Create', 'তৈরি করুন'),
  createKhataFailed(
    'Could not create khata. Please try again.',
    'খাতা তৈরি করা যায়নি। আবার চেষ্টা করুন।',
  ),
  openKhataFailed(
    'Could not open khata. Please try again.',
    'খাতা খোলা যায়নি। আবার চেষ্টা করুন।',
  ),
  nameUpTo40(
    'Enter a name of up to 40 characters',
    'সর্বোচ্চ ৪০ অক্ষরের নাম লিখুন',
  ),
  openingBalanceInput('Opening balance (₹)', 'প্রারম্ভিক জের (₹)'),
  openingBalanceRange(
    'Enter 0 to 999999999.99',
    '০ থেকে ৯৯৯৯৯৯৯৯৯.৯৯-এর মধ্যে লিখুন',
  ),
  loadKhatasFailed(
    'Could not load khatas. Please try again.',
    'খাতাগুলো দেখানো যায়নি। আবার চেষ্টা করুন।',
  ),
  updateKhataFailed(
    'Could not update khata. Please try again.',
    'খাতা হালনাগাদ করা যায়নি। আবার চেষ্টা করুন।',
  ),
  refreshKhatasFailed(
    'Updated khata, but could not refresh list. Please retry.',
    'খাতা হালনাগাদ হয়েছে, কিন্তু তালিকা বদলানো যায়নি। আবার চেষ্টা করুন।',
  ),
  archiveQuestion('Archive Khata?', 'খাতাটি সংরক্ষণাগারে রাখবেন?'),
  unarchiveQuestion('Unarchive Khata?', 'খাতাটি আবার সক্রিয় করবেন?'),
  archive('Archive', 'সংরক্ষণাগারে রাখুন'),
  unarchive('Unarchive', 'আবার সক্রিয় করুন'),
  back('Back', 'ফিরে যান'),
  retry('Retry', 'আবার চেষ্টা করুন'),
  dismiss('Dismiss', 'বন্ধ করুন'),
  activeKhatas('Active Khatas', 'সক্রিয় খাতা'),
  noActiveKhatas('No active khatas', 'কোনো সক্রিয় খাতা নেই'),
  archivedKhatas('Archived Khatas', 'সংরক্ষণাগারের খাতা'),
  noArchivedKhatas('No archived khatas', 'সংরক্ষণাগারে কোনো খাতা নেই'),
  defaultKhata('Default', 'ডিফল্ট খাতা'),
  renameKhata('Rename Khata', 'খাতার নাম বদলান'),

  // Wallet
  walletSummary('Wallet Summary', 'ওয়ালেটের সারাংশ'),
  reloadSummary('Reload summary', 'সারাংশ আবার দেখুন'),
  loadingWallet('Loading wallet summary', 'ওয়ালেটের সারাংশ লোড হচ্ছে'),
  readingKhatas('Reading your khatas…', 'আপনার খাতাগুলো পড়া হচ্ছে…'),
  readKhatasFailed('Could not read your khatas', 'আপনার খাতাগুলো পড়া যায়নি'),
  walletLoadExplanation(
    'Nothing is shown until the data loads, so totals are never guessed. Your saved entries are untouched.',
    'তথ্য না পাওয়া পর্যন্ত কোনো হিসাব দেখানো হয় না, তাই মোট টাকার অঙ্ক অনুমান করা হয় না। সংরক্ষিত লেনদেনে কোনো পরিবর্তন হয়নি।',
  ),
  noLocalKhatas(
    'No khatas on this device yet.',
    'এই ডিভাইসে এখনও কোনো খাতা নেই।',
  ),
  walletOpeningExplanation(
    'Income already includes each khata’s opening balance, so openings are never added twice.',
    'প্রতিটি খাতার প্রারম্ভিক জের আয়ের মধ্যে ধরা হয়েছে, তাই তা দুবার যোগ হয় না।',
  ),
  combinedRemaining('Combined remaining', 'সব খাতা মিলিয়ে অবশিষ্ট'),
  openingBalance('Opening balance', 'প্রারম্ভিক জের'),
  incomeIncludingOpening('Income (incl. opening)', 'আয় (প্রারম্ভিক জেরসহ)'),
  remaining('Remaining', 'অবশিষ্ট'),

  // Transactions and filter accessibility
  allTransactions('All Transactions', 'সব লেনদেন'),
  transactionUpdated('Transaction updated', 'লেনদেন হালনাগাদ হয়েছে'),
  transactionDeleted('Transaction deleted', 'লেনদেন মুছে ফেলা হয়েছে'),
  undo('Undo', 'আগের অবস্থায় ফেরান'),
  transactionRestored('Transaction restored', 'লেনদেন ফিরিয়ে আনা হয়েছে'),
  transactionRestoreFailed(
    'Could not restore transaction',
    'লেনদেন ফিরিয়ে আনা যায়নি',
  ),
  pickFromDay('Show transactions from this day', 'এই দিন থেকে লেনদেন দেখান'),
  pickToDay('Show transactions up to this day', 'এই দিন পর্যন্ত লেনদেন দেখান'),
  clearSearch('Clear search', 'খোঁজ মুছুন'),
  refreshTransactionsFailed(
    'Could not refresh transactions.',
    'লেনদেনের তালিকা হালনাগাদ করা যায়নি।',
  ),
  fromAnyDate('From: any date', 'শুরু: যেকোনো তারিখ'),
  toAnyDate('To: any date', 'শেষ: যেকোনো তারিখ'),
  fromAnyDateFilter(
    'Date filter: from any date',
    'তারিখের ফিল্টার: যেকোনো তারিখ থেকে',
  ),
  toAnyDateFilter(
    'Date filter: to any date',
    'তারিখের ফিল্টার: যেকোনো তারিখ পর্যন্ত',
  ),
  searchTransactions('Search transactions', 'লেনদেন খুঁজুন'),
  searchHint('Description or category', 'বিবরণ বা বিভাগ'),
  clearDates('Clear dates', 'তারিখ মুছুন'),
  clearDatesFilter(
    'Date filter: clear both days',
    'তারিখের ফিল্টার: দুটি তারিখই মুছুন',
  ),
  type('Type', 'ধরন'),
  all('All', 'সব'),
  allTypesFilter('Type filter: all entries', 'ধরনের ফিল্টার: সব লেনদেন'),
  incomeFilter('Type filter: income', 'ধরনের ফিল্টার: আয়'),
  expenseFilter('Type filter: expense', 'ধরনের ফিল্টার: ব্যয়'),
  allCategoriesFilter(
    'Category filter: all categories',
    'বিভাগের ফিল্টার: সব বিভাগ',
  ),
  filteredTotalsExplanation(
    'Totals count only the transactions shown, so the opening balance is excluded and this is not the remaining balance.',
    'মোটে শুধু দেখানো লেনদেনগুলো ধরা হয়েছে। এতে প্রারম্ভিক জের নেই এবং এটি অবশিষ্ট টাকার হিসাব নয়।',
  ),
  tapToEdit('Tap to edit', 'সম্পাদনা করতে চাপুন'),
  noTransactions('No transactions yet', 'এখনও কোনো লেনদেন নেই'),
  transactionsEmptyHelp(
    'Add your first entry from Home and it will appear here, newest first.',
    'মূল পাতা থেকে লেনদেন যোগ করুন। এখানে নতুন লেনদেন আগে দেখানো হবে।',
  ),
  noMatchingTransactions(
    'No transactions match these filters',
    'এই ফিল্টারের সঙ্গে কোনো লেনদেন মেলেনি',
  ),
  noMatchesHelp(
    'Try another search, type, category or date, or clear the filters to see every transaction again.',
    'অন্য শব্দ, ধরন, বিভাগ বা তারিখ দিয়ে খুঁজুন, অথবা সব লেনদেন দেখতে ফিল্টার মুছুন।',
  ),
  clearFilters('Clear filters', 'ফিল্টার মুছুন'),

  // Calculator and counter
  calculator('Calculator', 'ক্যালকুলেটর'),
  quickCalculation('Quick Calculation', 'দ্রুত হিসাব'),
  calculatorExpressionHint(
    'Enter an amount or expression',
    'টাকার পরিমাণ বা হিসাব লিখুন',
  ),
  invalidExpression('Invalid expression', 'হিসাবটি সঠিক নয়'),
  valueTooLarge('Value too large', 'মানটি অতিরিক্ত বড়'),
  valueTooSmall('Value too small', 'মানটি অতিরিক্ত ছোট'),
  expressionTooLong('Expression too long', 'হিসাবটি অতিরিক্ত দীর্ঘ'),
  divideByZero('Cannot divide by zero', 'শূন্য দিয়ে ভাগ করা যায় না'),
  clearCalculation('Clear', 'হিসাব মুছুন'),
  backspace('Backspace', 'শেষ অক্ষর মুছুন'),
  equals('Equals', 'সমান'),
  calculatorHistory('History', 'ইতিহাস'),
  calculatorHistoryEmpty('No history yet', 'এখনও কোনো ইতিহাস নেই'),
  clearHistory('Clear history', 'ইতিহাস মুছুন'),
  close('Close', 'বंद করুন'),
  counter('Counter', 'গণনা'),
  noteCounter('Note Counter', 'নোট গণনা'),
  negativeQuantity(
    'Quantity cannot be negative',
    'নোটের সংখ্যা ঋণাত্মক হতে পারে না',
  ),
  wholeNotes(
    'Enter a whole number of notes',
    'নোটের সংখ্যা পূর্ণ সংখ্যায় লিখুন',
  ),
  enterQuantity('Enter Quantity', 'সংখ্যা লিখুন'),
  totalAmount('Total Amount', 'মোট টাকা'),
  calculate('Calculate', 'হিসাব করুন'),
  newCount('New count', 'নতুন গণনা'),
  counterSession(
    'In-memory session - nothing is saved or added to a khata',
    'শুধু এই সেশনের জন্য — কিছুই সংরক্ষণ করা হয় না বা খাতায় যোগ হয় না',
  ),
  includeTwoThousand('Include ₹2,000 notes', '₹২,০০০-এর নোট ধরুন'),
  decreaseQuantity('Decrease quantity', 'সংখ্যা কমান'),
  increaseQuantity('Increase quantity', 'সংখ্যা বাড়ান'),
  grandTotal('Grand Total', 'সর্বমোট'),

  // Profile
  profile('Profile', 'প্রোফাইল'),
  appSettings('App Settings', 'অ্যাপ সেটিংস'),
  appDescription(
    'Offline-first personal khata. Data stays on this device.',
    'ইন্টারনেট ছাড়াই ব্যক্তিগত হিসাবের খাতা। তথ্য এই ডিভাইসেই থাকে।',
  ),
  webProfile(
    'Web design preview only. Local ledger storage and backup are not available on the web.',
    'শুধু ওয়েব প্রিভিউ। ওয়েবে ডিভাইসে খাতা বা ব্যাকআপ রাখার সুবিধা নেই।',
  ),
  accountAndBackup('Account & backup', 'অ্যাকাউন্ট ও ব্যাকআপ'),
  settingsDescription('Language and app preferences.', 'ভাষা ও অ্যাপের পছন্দ।'),
  myWalletSummary('My Wallet Summary', 'আমার ওয়ালেটের সারাংশ'),
  walletDescription(
    'Opening balance, income and expense for each khata.',
    'প্রতিটি খাতার প্রারম্ভিক জের, আয় ও ব্যয়।',
  ),
  notAvailable('Not available yet', 'এখনও উপলব্ধ নয়'),
  backupDescription(
    'Save or restore an unencrypted local backup file.',
    'এনক্রিপশন ছাড়া স্থানীয় ব্যাকআপ ফাইল সংরক্ষণ করুন বা তা থেকে তথ্য ফেরান।',
  ),
  signIn('Sign in', 'সাইন ইন করুন'),
  signInUnavailable(
    'Accounts and cloud sync are not available in this build. Your khata stays on this device.',
    'এই সংস্করণে অ্যাকাউন্ট ও ক্লাউড সিঙ্কের সুবিধা নেই। আপনার খাতা এই ডিভাইসেই থাকে।',
  ),
  about('About Khoroch Diary', 'খরচের ডায়েরি সম্পর্কে'),
  version('Version', 'সংস্করণ'),
  dataLocation('Where your data lives', 'আপনার তথ্য কোথায় থাকে'),
  thisDeviceOnly('This device only', 'শুধু এই ডিভাইসে'),
  money('Money', 'মুদ্রা'),
  profileCurrency(
    'Indian rupees (INR), Indian digit grouping',
    'ভারতীয় রুপি (INR), ভারতীয় নিয়মে অঙ্কের বিন্যাস',
  ),
  lightOnly('Light only', 'শুধু হালকা থিম'),
  licences('Open-source licences', 'ওপেন সোর্স লাইসেন্স'),
  licencesDescription(
    'Software Khoroch Diary is built with.',
    'খরচের ডায়েরি তৈরিতে ব্যবহৃত সফটওয়্যার।',
  ),
  localProfile('Local profile', 'ডিভাইসের প্রোফাইল'),
  notSignedIn('Not signed in', 'সাইন ইন করা হয়নি'),
  localProfileDescription(
    'No account is linked to Khoroch Diary. Everything you enter stays in the local database on this device.',
    'খরচের ডায়েরিের সঙ্গে কোনো অ্যাকাউন্ট যুক্ত নেই। আপনার দেওয়া তথ্য এই ডিভাইসের ডেটাবেসেই থাকে।',
  ),
  offlineLocalOnly('Offline & local-only', 'অফলাইন, শুধু ডিভাইসে'),
  offlinePrivacy(
    'Khoroch Diary works without internet. Entries are saved on this device, nothing is uploaded, and there is no cloud copy to restore.',
    'খরচের ডায়েরি ইন্টারনেট ছাড়াই চলে। লেনদেন এই ডিভাইসে থাকে, কিছুই আপলোড হয় না এবং ফেরানোর মতো কোনো ক্লাউড কপি নেই।',
  ),

  // Settings
  preferences('Preferences', 'পছন্দ'),
  currency('Currency', 'মুদ্রা'),
  currencyDetail(
    'All amounts use Indian rupees.',
    'সব অঙ্ক ভারতীয় রুপিতে দেখানো হয়।',
  ),
  currencyInr('INR (₹)', 'ভারতীয় রুপি (₹)'),
  fixed('Fixed in v1', 'প্রথম সংস্করণে নির্ধারিত'),
  theme('Theme', 'থিম'),
  themeDetail(
    'The app uses a light theme.',
    'অ্যাপে হালকা থিম ব্যবহার করা হয়।',
  ),
  light('Light', 'হালকা'),
  language('Language', 'ভাষা'),
  languageUnavailable(
    'Language change is not available here.',
    'এখানে ভাষা বদলানোর সুবিধা নেই।',
  ),
  changeLanguage('Change language', 'ভাষা বদলান'),
  languageDetail('Choose English or Bengali.', 'ইংরেজি বা বাংলা বেছে নিন।'),
  languagePending(
    'Saving language preference…',
    'ভাষার পছন্দ সংরক্ষণ করা হচ্ছে…',
  ),
  languageFailed(
    'Could not save the language preference. Please try again.',
    'ভাষার পছন্দ সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।',
  ),
  cloudBackup('Cloud backup', 'ক্লাউড ব্যাকআপ'),
  cloudDetail(
    'Accounts, cloud backup and cloud sync are unavailable in this build.',
    'এই সংস্করণে অ্যাকাউন্ট, ক্লাউড ব্যাকআপ ও ক্লাউড সিঙ্ক নেই।',
  ),
  off('Off', 'বন্ধ'),
  storage('Storage', 'তথ্য সংরক্ষণ'),
  storageTitle('Your data', 'আপনার তথ্য'),
  storageDetail(
    'Your entries are saved on this device.',
    'আপনার লেনদেন এই ডিভাইসেই সংরক্ষিত থাকে।',
  ),
  thisDevice('This device', 'এই ডিভাইস'),
  localOnly('Local only', 'শুধু ডিভাইসে'),
  settingsBackupHint(
    'Back up or restore from Profile.',
    'প্রোফাইল থেকে ব্যাকআপ নিন বা পুনরুদ্ধার করুন।',
  ),
  internetRequired('Internet required', 'ইন্টারনেট প্রয়োজন'),
  internetDetail(
    'The app works offline and does not upload your ledger.',
    'অ্যাপ অফলাইনে চলে এবং আপনার খাতার তথ্য আপলোড করে না।',
  ),
  no('No', 'না'),
  offlineFirst('Offline-first', 'অফলাইনকে অগ্রাধিকার'),
  readOnly('Read-only in this build', 'এই সংস্করণে শুধু দেখা যাবে'),
  readOnlyDetail(
    'Nothing on this screen can be changed, and no preference is saved.',
    'এই পর্দায় কিছু বদলানো যায় না, কোনো পছন্দও সংরক্ষিত হয় না।',
  ),
  webSettings(
    'Web design preview only. Local ledger storage, preferences and backup are not available on the web.',
    'শুধু ওয়েব প্রিভিউ। ওয়েবে খাতা, পছন্দ বা ব্যাকআপ সংরক্ষণের সুবিধা নেই।',
  ),
  androidBackup('Android only', 'শুধু অ্যান্ড্রয়েডে'),
  androidBackupDetail(
    'Android can export and restore an unencrypted offline JSON file. It contains khatas and transactions, but excludes profile and note-count data. Keep it somewhere private.',
    'অ্যান্ড্রয়েডে এনক্রিপশন ছাড়া অফলাইন JSON ফাইল রপ্তানি ও পুনরুদ্ধার করা যায়। এতে খাতা ও লেনদেন থাকে, তবে প্রোফাইল ও নোট গণনার তথ্য থাকে না। ফাইলটি ব্যক্তিগত ও নিরাপদ স্থানে রাখুন।',
  ),

  // Offline backup and restore
  backupRestore('Backup / Restore', 'ব্যাকআপ / পুনরুদ্ধার'),
  offlineBackupRestore(
    'Offline backup / restore',
    'অফলাইন ব্যাকআপ / পুনরুদ্ধার',
  ),
  backupPrivacy(
    'Warning: backups may contain sensitive, unencrypted financial data. Choose a safe location.',
    'সতর্কতা: ব্যাকআপে এনক্রিপশন ছাড়া সংবেদনশীল আর্থিক তথ্য থাকতে পারে। নিরাপদ স্থান বেছে নিন।',
  ),
  exportingBackup('Exporting backup…', 'ব্যাকআপ রপ্তানি হচ্ছে…'),
  exportBackup('Export Backup', 'ব্যাকআপ রপ্তানি করুন'),
  exportSaved('Export saved successfully.', 'ব্যাকআপ সংরক্ষিত হয়েছে।'),
  exportCancelled('Export cancelled.', 'রপ্তানি বাতিল হয়েছে।'),
  exportFailed('Export failed.', 'রপ্তানি করা যায়নি।'),
  pickingBackup('Picking backup…', 'ব্যাকআপ ফাইল বেছে নেওয়া হচ্ছে…'),
  pickBackup('Pick Backup to Restore', 'পুনরুদ্ধারের জন্য ব্যাকআপ বেছে নিন'),
  pickCancelled('Pick cancelled.', 'ফাইল বাছাই বাতিল হয়েছে।'),
  backupValidationFailed(
    'Could not read or validate the backup.',
    'ব্যাকআপ পড়া বা যাচাই করা যায়নি।',
  ),
  backupTooLarge('Backup is too large.', 'ব্যাকআপ ফাইলটি অতিরিক্ত বড়।'),
  reviewRestore(
    'Review the confirmation before restoring.',
    'পুনরুদ্ধারের আগে নিশ্চিতকরণ বার্তাটি পড়ুন।',
  ),
  restoreQuestion('Restore Backup?', 'ব্যাকআপ থেকে তথ্য ফেরাবেন?'),
  restoreWarning(
    'Warning: all current khatas and transactions on this device will be replaced. This cannot be undone.',
    'সতর্কতা: এই ডিভাইসের বর্তমান সব খাতা ও লেনদেন প্রতিস্থাপিত হবে। এই কাজ পূর্বাবস্থায় ফেরানো যাবে না।',
  ),
  confirmRestore('Confirm Restore', 'পুনরুদ্ধার নিশ্চিত করুন'),
  confirmReplaceAll(
    'Confirm Restore (Replace ALL Data)',
    'পুনরুদ্ধার নিশ্চিত করুন (সব খাতা ও লেনদেন বদলাবে)',
  ),
  restoreFailed(
    'Restore failed. Your current data was not replaced.',
    'পুনরুদ্ধার করা যায়নি। আপনার বর্তমান তথ্য বদলায়নি।',
  ),
  restoreCancelled('Restore cancelled.', 'পুনরুদ্ধার বাতিল হয়েছে।'),
  backupRestored('Backup restored.', 'ব্যাকআপ থেকে তথ্য ফেরানো হয়েছে।');

  const AppString(this.en, this.bn);

  final String en;
  final String bn;
}

/// Immutable display helpers. Dates keep the supplied time zone, and money
/// always uses INR and the existing integer-paise formatter. Localized output
/// is for display, not for parsing into editor fields or exporting to JSON.
class AppStrings {
  const AppStrings([this.language = AppLanguage.en]);

  factory AppStrings.fromCode(String? code) =>
      AppStrings(AppLanguage.fromCode(code));

  final AppLanguage language;

  bool get _bn => language == AppLanguage.bn;

  String text(AppString key) => _bn ? key.bn : key.en;

  String onboardingPageLabel(int current, int total) => _bn
      ? 'পরিচিতির পৃষ্ঠা ${number(current)}, মোট ${number(total)}টি'
      : 'Introduction page $current of $total';

  String _digits(String text) => _bn
      ? text.replaceAllMapped(
          RegExp('[0-9]'),
          (match) => '০১২৩৪৫৬৭৮৯'[int.parse(match[0]!)],
        )
      : text;

  String number(int count) => _digits(count.toString());

  String money(int paise) => _digits(formatPaise(paise));

  String _month(DateTime value) {
    const en = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const bn = [
      'জানুয়ারি',
      'ফেব্রুয়ারি',
      'মার্চ',
      'এপ্রিল',
      'মে',
      'জুন',
      'জুলাই',
      'আগস্ট',
      'সেপ্টেম্বর',
      'অক্টোবর',
      'নভেম্বর',
      'ডিসেম্বর',
    ];
    return (_bn ? bn : en)[value.month - 1];
  }

  String monthYear(DateTime value) {
    final String month = _month(value);
    return '$month ${number(value.year)}';
  }

  String day(DateTime value) =>
      '${_digits(value.day.toString().padLeft(2, '0'))} ${monthYear(value)}';

  String dateTime(DateTime value) {
    if (!_bn) return formatEntryDate(value);
    final int hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final String minute = _digits(value.minute.toString().padLeft(2, '0'));
    final String marker = value.hour < 12 ? 'পূর্বাহ্ণ' : 'অপরাহ্ণ';
    return '${day(value)}, ${number(hour)}:$minute $marker';
  }

  String afterSave(int? paise) {
    final String amount = paise == null ? '—' : money(paise);
    return _bn ? 'সংরক্ষণের পর: $amount' : 'After saving: $amount';
  }

  String entryCount(int count) => _bn
      ? '${number(count)}টি লেনদেন'
      : '$count ${count == 1 ? 'entry' : 'entries'}';

  String acrossKhatas(int count) => _bn
      ? '${number(count)}টি খাতা মিলিয়ে'
      : 'Across $count ${count == 1 ? 'khata' : 'khatas'}';

  String transactionCount({required int shown, required int total}) {
    if (_bn) {
      return shown == total
          ? '${number(total)}টি লেনদেন দেখানো হচ্ছে'
          : 'মোট ${number(total)}টির মধ্যে ${number(shown)}টি লেনদেন দেখানো হচ্ছে';
    }
    final String noun = total == 1 ? 'transaction' : 'transactions';
    return shown == total
        ? 'Showing $total $noun'
        : 'Showing $shown of $total $noun';
  }

  /// Count-only by design. Do not include raw JSON or exception messages.
  String backupPreview({
    required int khatas,
    required int transactions,
    required int deleted,
    bool loaded = false,
  }) {
    if (_bn) {
      final String title = loaded ? 'প্রিভিউ প্রস্তুত' : 'প্রিভিউ';
      return '$title: ${number(khatas)}টি খাতা, '
          '${number(transactions)}টি লেনদেন, ${number(deleted)}টি মোছা হয়েছে।';
    }
    final String title = loaded ? 'Preview loaded' : 'Preview';
    return '$title: $khatas ${khatas == 1 ? 'khata' : 'khatas'}, '
        '$transactions ${transactions == 1 ? 'transaction' : 'transactions'}, '
        '$deleted deleted.';
  }

  String nameLength(int maximum) => _bn
      ? '১ থেকে ${number(maximum)} অক্ষরের নাম লিখুন'
      : 'Enter a name of 1 to $maximum characters';

  String dateFilter({
    required bool from,
    DateTime? date,
    bool semantic = false,
  }) {
    if (date == null) {
      return text(
        from
            ? (semantic ? AppString.fromAnyDateFilter : AppString.fromAnyDate)
            : (semantic ? AppString.toAnyDateFilter : AppString.toAnyDate),
      );
    }
    final String label = day(date);
    if (_bn) {
      if (semantic) {
        return 'তারিখের ফিল্টার: $label ${from ? 'থেকে' : 'পর্যন্ত'}';
      }
      return '${from ? 'শুরু' : 'শেষ'}: $label';
    }
    return semantic
        ? 'Date filter: ${from ? 'from' : 'to'} $label'
        : '${from ? 'From' : 'To'}: $label';
  }

  // Names are displayed verbatim, never translated or included in errors.
  String archiveConfirmation(String name) => _bn
      ? '“$name” সংরক্ষণাগারে রাখবেন? লেনদেনগুলো থাকবে, তবে সক্রিয় খাতার তালিকায় এটি আর দেখা যাবে না।'
      : 'Archive “$name”? Its entries will be retained, but this khata '
            'will be hidden from the active switcher.';

  String unarchiveConfirmation(String name) => _bn
      ? '“$name” সক্রিয় খাতার তালিকায় ফেরাবেন?'
      : 'Restore “$name” to your active khatas?';

  String renameLabel(String name) =>
      _bn ? '$name-এর নাম বদলান' : 'Rename $name';

  String archiveLabel(String name) =>
      _bn ? '$name সংরক্ষণাগারে রাখুন' : 'Archive $name';

  String categoryLabel(String category, {bool filter = false}) {
    if (_bn) return '${filter ? 'বিভাগের ফিল্টার:' : 'বিভাগ:'} $category';
    return '${filter ? 'Category filter:' : 'Category'} $category';
  }

  String noteLabel(int paise, {bool quantity = false}) {
    final String amount = money(paise);
    if (_bn) return quantity ? '$amount-এর নোটের সংখ্যা' : '$amount-এর নোট';
    return quantity ? 'Quantity of $amount notes' : '$amount note';
  }

  String hiddenNotes(int count) => _bn
      ? '${money(200000)} × ${number(count)} ধরা হয়েছে (নোটের মান লুকানো)'
      : 'Includes ${money(200000)} × $count (denomination hidden)';

  String walletTotal({required int khatas, required int paise}) =>
      '${text(AppString.combinedRemaining)}, ${acrossKhatas(khatas)}: '
      '${money(paise)}. ${text(AppString.walletOpeningExplanation)}';

  /// [paise] is a positive magnitude; [income] supplies the display sign.
  String signedMoney(int paise, {required bool income}) =>
      '${income ? '+' : '-'}${money(paise)}';

  String transactionLabel({
    required String title,
    required String category,
    required int amountPaise,
    required bool income,
    required DateTime at,
    bool editable = false,
  }) {
    final String direction = text(
      income ? AppString.income : AppString.expense,
    );
    final String amount = signedMoney(amountPaise, income: income);
    final String edit = editable ? ', ${text(AppString.tapToEdit)}' : '';
    return '$title, $category, $direction $amount, ${dateTime(at)}$edit';
  }

  String buildLabel(String version, int build) => _bn
      ? '${text(AppString.appName)} ${_digits(version)} (বিল্ড ${number(build)})'
      : '${text(AppString.appName)} $version (build $build)';

  String flowTotals({required int incomePaise, required int expensePaise}) =>
      '${text(AppString.income)} ${money(incomePaise)}, '
      '${text(AppString.expense)} ${money(expensePaise)}.';
}
