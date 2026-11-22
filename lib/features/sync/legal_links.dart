// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';

const String privacyPolicyUrl =
    'https://keshab1997.github.io/khoroch-diary/privacy-policy.html';
const String termsOfUseUrl =
    'https://keshab1997.github.io/khoroch-diary/terms-of-use.html';
const String accountDeletionUrl =
    'https://keshab1997.github.io/khoroch-diary/account-deletion.html';

/// Links to public policy resources, shown before optional cloud sign-in.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key, required this.bengali});

  final bool bengali;

  @override
  Widget build(BuildContext context) {
    Future<void> open(String value) async {
      final Uri uri = Uri.parse(value);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              bengali
                  ? 'লিংকটি খোলা যায়নি। আবার চেষ্টা করুন।'
                  : 'Could not open the link. Please try again.',
            ),
          ),
        );
      }
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 0,
      children: <Widget>[
        TextButton(
          key: const Key('legal-privacy-link'),
          onPressed: () => open(privacyPolicyUrl),
          style: TextButton.styleFrom(foregroundColor: AppColors.primaryGreen),
          child: Text(bengali ? 'গোপনীয়তা নীতি' : 'Privacy Policy'),
        ),
        TextButton(
          key: const Key('legal-terms-link'),
          onPressed: () => open(termsOfUseUrl),
          style: TextButton.styleFrom(foregroundColor: AppColors.primaryGreen),
          child: Text(bengali ? 'ব্যবহারের শর্ত' : 'Terms of Use'),
        ),
        TextButton(
          key: const Key('legal-delete-link'),
          onPressed: () => open(accountDeletionUrl),
          style: TextButton.styleFrom(foregroundColor: AppColors.primaryGreen),
          child: Text(bengali ? 'অ্যাকাউন্ট মুছুন' : 'Delete account'),
        ),
      ],
    );
  }
}
