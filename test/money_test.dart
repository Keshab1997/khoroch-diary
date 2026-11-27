import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/format/money.dart';

void main() {
  group('parsePaise', () {
    test('reads rupees with up to two decimals as integer paise', () {
      expect(parsePaise('1'), 100);
      expect(parsePaise('1200'), 120000);
      expect(parsePaise('1200.5'), 120050);
      expect(parsePaise('1200.50'), 120050);
      expect(parsePaise('0.5'), 50);
      expect(parsePaise('0.05'), 5);
    });

    test('takes the largest ledger amount and nothing above it', () {
      expect(parsePaise('999999999.99'), 99999999999);
      expect(parsePaise('1000000000'), isNull);
    });

    test('Bengali digits read as the digits they stand for', () {
      expect(parsePaise('৫০'), 5000);
      expect(parsePaise('৫৮০.২৫'), 58025);
    });

    test('rejects text that is not a plain amount', () {
      for (final String bad in <String>[
        '',
        ' ',
        'abc',
        '.5',
        '5.',
        '1.234',
        '1,000',
        '-5',
        '+5',
        '1e3',
        ' 12',
        '12 ',
        '007',
        '00.5',
        '01',
      ]) {
        expect(parsePaise(bad), isNull, reason: '"$bad"');
      }
    });

    test('zero is not an amount unless asked for', () {
      expect(parsePaise('0'), isNull);
      expect(parsePaise('0.00'), isNull);
      expect(parsePaise('0', allowZero: true), 0);
      expect(parsePaise('0.00', allowZero: true), 0);
    });

    test('leading zeros are rejected unless asked for', () {
      expect(parsePaise('05000'), isNull);
      expect(parsePaise('05000', allowLeadingZeros: true), 500000);
      expect(parsePaise('০৫০০০', allowLeadingZeros: true), 500000);
      expect(parsePaise('00.5', allowLeadingZeros: true), 50);
      expect(parsePaise('000', allowLeadingZeros: true, allowZero: true), 0);
      // Dropping the zeros does not make the rest of the text acceptable.
      expect(parsePaise('05.', allowLeadingZeros: true), isNull);
      expect(parsePaise('0abc', allowLeadingZeros: true), isNull);
    });
  });
}
