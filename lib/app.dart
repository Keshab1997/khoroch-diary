// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'core/l10n/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_colors.dart';
import 'features/shell/main_shell.dart';
import 'features/ledger/data/local_ledger.dart';
import 'features/sync/cloud_sync.dart';

class KhorochDiaryApp extends StatelessWidget {
  const KhorochDiaryApp({
    super.key,
    this.ledger,
    this.cloudSync,
    this.initialLanguage = AppLanguage.en,
  });

  final LocalLedger? ledger;

  /// The live cloud sync service started in `main`. `null` (tests, web
  /// preview, or an unconfigured build) means the app stays purely local.
  final CloudSync? cloudSync;

  /// The language saved on this device, read before the first frame.
  final AppLanguage initialLanguage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Khoroch Diary',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      builder: (context, child) => Container(
        color: AppColors.navigationGrey.withAlpha(51),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: child!,
          ),
        ),
      ),
      home: MainShell(
        ledger: ledger,
        cloudSync: cloudSync,
        initialLanguage: initialLanguage,
      ),
    );
  }
}
