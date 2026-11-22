import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart';

void main() {
  const en = AppStrings();
  const bn = AppStrings(AppLanguage.bn);

  test('all typed keys have distinct English and Bengali UI copy', () {
    final bengali = RegExp('[\u0980-\u09FF]');
    for (final key in AppString.values) {
      expect(en.text(key).trim(), isNotEmpty, reason: key.name);
      expect(bengali.hasMatch(en.text(key)), isFalse, reason: key.name);
      expect(bengali.hasMatch(bn.text(key)), isTrue, reason: key.name);
      expect(bn.text(key), isNot(en.text(key)), reason: key.name);
    }
    const requiredKeys = {
      AppString.homeEmpty,
      AppString.descriptionTooLong,
      AppString.deleteQuestion,
      AppString.openingBalanceRange,
      AppString.archiveQuestion,
      AppString.walletOpeningExplanation,
      AppString.noMatchesHelp,
      AppString.clearDatesFilter,
      AppString.divideByZero,
      AppString.wholeNotes,
      AppString.offlinePrivacy,
      AppString.languageFailed,
      AppString.androidBackupDetail,
      AppString.backupPrivacy,
      AppString.backupValidationFailed,
      AppString.restoreWarning,
      AppString.restoreFailed,
    };
    expect(AppString.values, containsAll(requiredKeys));
    expect(bn.text(AppString.income), 'আয়');
    expect(bn.text(AppString.expense), 'ব্যয়');
  });

  test('supported tags resolve and unsupported languages fall back', () {
    for (final tag in ['bn', 'bn-IN', ' BN_bd ']) {
      expect(AppStrings.fromCode(tag).language, AppLanguage.bn);
    }
    for (final tag in [null, '', 'en-GB', 'fr', 'bng']) {
      expect(AppStrings.fromCode(tag).language, AppLanguage.en);
    }
  });

  test('INR formatting preserves integer paise, signs and grouping', () {
    expect(en.money(-123456789), '-₹12,34,567.89');
    expect(bn.money(-123456789), '-₹১২,৩৪,৫৬৭.৮৯');
    expect(bn.money(1), '₹০.০১');
    expect(bn.money(500), '₹৫');
    expect(bn.afterSave(null), contains('—'));
    expect(bn.afterSave(-1), contains('-₹০.০১'));
    expect(
      bn.flowTotals(incomePaise: 125, expensePaise: 75),
      'আয় ₹১.২৫, ব্যয় ₹০.৭৫.',
    );
  });

  test('dates preserve year and clock values, including noon and midnight', () {
    final noon = DateTime.utc(2026, 11, 9, 12, 7);
    expect(en.dateTime(noon), '09 Nov 2026, 12:07 PM');
    expect(bn.dateTime(noon), '০৯ নভেম্বর ২০২৬, ১২:০৭ অপরাহ্ণ');
    expect(
      bn.dateTime(DateTime(2026, 11, 9)),
      '০৯ নভেম্বর ২০২৬, ১২:০০ পূর্বাহ্ণ',
    );
    expect(bn.monthYear(noon), 'নভেম্বর ২০২৬');
    expect(
      bn.dateFilter(from: false, date: noon, semantic: true),
      'তারিখের ফিল্টার: ০৯ নভেম্বর ২০২৬ পর্যন্ত',
    );
    expect(en.dateFilter(from: true), 'From: any date');
  });

  test('count helpers preserve zero, singular, plural and partial results', () {
    expect(en.entryCount(0), '0 entries');
    expect(en.entryCount(1), '1 entry');
    expect(en.acrossKhatas(42), 'Across 42 khatas');
    expect(bn.acrossKhatas(42), '৪২টি খাতা মিলিয়ে');
    expect(en.transactionCount(shown: 1, total: 1), 'Showing 1 transaction');
    expect(
      bn.transactionCount(shown: 0, total: 23),
      'মোট ২৩টির মধ্যে ০টি লেনদেন দেখানো হচ্ছে',
    );
    expect(bn.hiddenNotes(10), contains('₹২,০০০ × ১০'));
    expect(bn.nameLength(40), contains('৪০'));
  });

  test('backup preview only reports counts; validation has no payload', () {
    expect(
      en.backupPreview(khatas: 1, transactions: 12, deleted: 0),
      'Preview: 1 khata, 12 transactions, 0 deleted.',
    );
    expect(
      bn.backupPreview(khatas: 2, transactions: 12, deleted: 3, loaded: true),
      'প্রিভিউ প্রস্তুত: ২টি খাতা, ১২টি লেনদেন, ৩টি মোছা হয়েছে।',
    );
    expect(
      en.text(AppString.backupValidationFailed),
      'Could not read or validate the backup.',
    );
    expect(en.text(AppString.backupPrivacy), contains('unencrypted'));
    expect(en.text(AppString.restoreWarning), contains('cannot be undone'));
  });
}
