import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/config/cloud_project.dart';
import 'package:khoroch_diary/features/sync/cloud_config.dart';

void main() {
  test('the default environment config is the baked-in project', () {
    const CloudConfig config = CloudConfig.fromEnvironment();
    expect(config.isConfigured, isTrue);
    expect(config.url, kSupabaseUrl);
    expect(config.publishableKey, kSupabasePublishableKey);
    expect(
      config.redirectTo,
      kIsWeb ? isNull : 'com.keshabstudios.khorochdiary://login-callback',
    );
  });

  test(
    'the cloud project URL is the HTTPS address of the Khoroch Diary project',
    () {
      final Uri url = Uri.parse(kSupabaseUrl);
      expect(url.scheme, 'https');
      expect(url.host, 'kajgkcevlhhcsnyvjxvy.supabase.co');
      expect(url.path, isEmpty);
      expect(url.hasQuery, isFalse);
    },
  );

  test('the key kept in code is the publishable one', () {
    expect(kSupabasePublishableKey, startsWith('sb_publishable_'));
    expect(kSupabasePublishableKey.trim(), kSupabasePublishableKey);
  });

  test('no secret or service-role key appears anywhere in lib/', () {
    // New-format secret keys have a fixed prefix; legacy keys are JWTs whose
    // payload names the role, so decode every JWT-shaped literal and check it.
    final RegExp secretPrefix = RegExp(
      'sb_'
      'secret_',
    );
    final RegExp jwt = RegExp(
      r'eyJ[A-Za-z0-9_-]+\.(eyJ[A-Za-z0-9_-]+)\.[A-Za-z0-9_-]+',
    );
    final List<File> sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.endsWith('.dart'))
        .toList();
    expect(sources, isNotEmpty);
    for (final File file in sources) {
      final String text = file.readAsStringSync();
      expect(secretPrefix.hasMatch(text), isFalse, reason: file.path);
      for (final RegExpMatch match in jwt.allMatches(text)) {
        final Object? claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(match.group(1)!))),
        );
        expect(
          claims is Map && claims['role'] == 'service_role',
          isFalse,
          reason: '${file.path} holds a service-role key',
        );
      }
    }
  });
}
