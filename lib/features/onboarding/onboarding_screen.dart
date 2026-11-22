// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.language,
    required this.onLanguageChanged,
    required this.onComplete,
  });

  final AppLanguage language;
  final Future<void> Function(AppLanguage language) onLanguageChanged;
  final Future<void> Function() onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _pageCount = 4;
  static const List<String> _illustrations = <String>[
    'assets/onboarding/ledger.jpg',
    'assets/onboarding/offline.jpg',
    'assets/onboarding/multiple-khatas.jpg',
    'assets/onboarding/tools-backup.jpg',
  ];

  final PageController _pageController = PageController();
  int _page = 0;
  bool _finishing = false;

  AppStrings get _strings => AppStrings(widget.language);

  Future<void> _setLanguage() async {
    if (_finishing) return;
    final AppLanguage next = widget.language == AppLanguage.en
        ? AppLanguage.bn
        : AppLanguage.en;
    await widget.onLanguageChanged(next);
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await widget.onComplete();
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  void _next() {
    if (_page == _pageCount - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _previous() {
    if (_page == 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = _strings;
    final bool isLastPage = _page == _pageCount - 1;

    return Scaffold(
      key: const Key('onboarding-screen'),
      backgroundColor: AppColors.creamBackground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    strings.text(AppString.appName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.primaryGreen,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    children: <Widget>[
                      TextButton(
                        key: const Key('onboarding-language-button'),
                        onPressed: _finishing ? null : _setLanguage,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primaryGreen,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text(strings.text(AppString.onboardingLanguage)),
                      ),
                      TextButton(
                        key: const Key('onboarding-skip-button'),
                        onPressed: _finishing ? null : _finish,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.softText,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text(strings.text(AppString.onboardingSkip)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                key: const Key('onboarding-pages'),
                controller: _pageController,
                itemCount: _pageCount,
                onPageChanged: (int page) => setState(() => _page = page),
                itemBuilder: (BuildContext context, int index) {
                  final AppString title = switch (index) {
                    0 => AppString.onboardingOneTitle,
                    1 => AppString.onboardingTwoTitle,
                    2 => AppString.onboardingThreeTitle,
                    _ => AppString.onboardingFourTitle,
                  };
                  final AppString body = switch (index) {
                    0 => AppString.onboardingOneBody,
                    1 => AppString.onboardingTwoBody,
                    2 => AppString.onboardingThreeBody,
                    _ => AppString.onboardingFourBody,
                  };
                  return _OnboardingPage(
                    illustration: _illustrations[index],
                    title: strings.text(title),
                    body: strings.text(body),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Semantics(
                key: const Key('onboarding-page-indicator'),
                label: strings.onboardingPageLabel(_page + 1, _pageCount),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List<Widget>.generate(_pageCount, (int index) {
                    final bool selected = index == _page;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: selected ? 24 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primaryGreen
                            : AppColors.beige,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    );
                  }),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: <Widget>[
                  if (_page > 0) ...<Widget>[
                    IconButton(
                      key: const Key('onboarding-back-button'),
                      onPressed: _finishing ? null : _previous,
                      tooltip: strings.text(AppString.onboardingBack),
                      style: IconButton.styleFrom(
                        foregroundColor: AppColors.primaryGreen,
                        backgroundColor: AppColors.warmIvory,
                        minimumSize: const Size(52, 52),
                        side: const BorderSide(color: AppColors.outline),
                      ),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: FilledButton(
                      key: Key(
                        isLastPage
                            ? 'onboarding-start-button'
                            : 'onboarding-next-button',
                      ),
                      onPressed: _finishing ? null : _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: AppColors.onPrimary,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        strings.text(
                          isLastPage
                              ? AppString.onboardingStart
                              : AppString.onboardingNext,
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.illustration,
    required this.title,
    required this.body,
  });

  final String illustration;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.sizeOf(context).height * 0.30,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Image.asset(
              illustration,
              width: MediaQuery.sizeOf(context).width < 360 ? 190 : 224,
              height: MediaQuery.sizeOf(context).width < 360 ? 190 : 224,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(height: 18),
            Text(
              title,
              key: const Key('onboarding-page-title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.darkText,
                fontSize: 25,
                height: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              body,
              key: const Key('onboarding-page-body'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.softText,
                fontSize: 16,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
