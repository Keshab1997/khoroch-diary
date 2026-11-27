/// Money lives in the database as **integer paise**. This is the only layer
/// that turns it into text, using Indian digit grouping (₹1,00,000) and the
/// rupee symbol, and the only one that reads an amount a person typed back
/// into paise. No `double`, no `intl` locale data, no network.
String formatPaise(int paise) {
  final int absolute = paise.abs();
  final int rupees = absolute ~/ 100;
  final int fraction = absolute % 100;
  final String fractionText = fraction == 0
      ? ''
      : '.${fraction.toString().padLeft(2, '0')}';
  final String sign = paise < 0 ? '-' : '';
  final String grouped = _groupIndian(rupees.toString());
  return '$sign₹$grouped$fractionText';
}

/// Rupees as typed into an amount field: at most nine rupee digits (the
/// ledger's largest amount, ₹99,99,99,999.99), no leading zeros (`007` and
/// `00.5` are not amounts) and at most two decimals.
final RegExp _typedAmount = RegExp(r'^(0|[1-9]\d{0,8})(?:\.(\d{1,2}))?$');

final RegExp _bengaliDigit = RegExp('[০-৯]');
final RegExp _leadingZeros = RegExp(r'^0+(?=\d)');

/// Reads rupees a person typed (`1200`, `1200.5`, `1200.50`) as integer paise,
/// or `null` when the text is not such an amount. It never goes through
/// `double`, so no amount is off by a paisa.
///
/// Bengali digits (০-৯) count as the digits they stand for, so every amount
/// field accepts what a Bengali keyboard types. Zero is not an amount unless
/// [allowZero] (an opening balance may be zero), and [allowLeadingZeros] reads
/// `05000` as 5000, for a field that starts out prefilled with `0`.
int? parsePaise(
  String input, {
  bool allowZero = false,
  bool allowLeadingZeros = false,
}) {
  String text = input.replaceAllMapped(
    _bengaliDigit,
    (Match digit) => '০১২৩৪৫৬৭৮৯'.indexOf(digit[0]!).toString(),
  );
  if (allowLeadingZeros) {
    text = text.replaceFirst(_leadingZeros, '');
  }
  final Match? match = _typedAmount.firstMatch(text);
  if (match == null) {
    return null;
  }
  final int rupees = int.parse(match[1]!);
  final int paise = int.parse((match[2] ?? '').padRight(2, '0'));
  final int amount = rupees * 100 + paise;
  return (amount > 0 || allowZero) ? amount : null;
}

/// Indian grouping: the last three digits, then pairs (1,00,000 not 100,000).
String _groupIndian(String digits) {
  if (digits.length <= 3) {
    return digits;
  }
  final String lastThree = digits.substring(digits.length - 3);
  String rest = digits.substring(0, digits.length - 3);
  final List<String> groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) {
    groups.insert(0, rest);
  }
  return '${groups.join(',')},$lastThree';
}
