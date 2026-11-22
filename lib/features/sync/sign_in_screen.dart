// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart' show AppLanguage;
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ledger_header_background.dart';
import 'cloud_backend.dart';

/// The single soft card shadow from `theme.md` (blur 14, offset 0/4).
List<BoxShadow> _cardShadow() => <BoxShadow>[
  BoxShadow(
    color: AppColors.darkText.withValues(alpha: 0.05),
    blurRadius: 14,
    offset: const Offset(0, 4),
  ),
];

/// The one radius every account surface uses: the header's lower corners and
/// every card on these screens, so the family reads as one shape.
const double _accountRadius = 20;

/// The header's lower edge: the same fine golden rule the Home balance card and
/// the Counter banner carry, at the weight a page header can afford (2 dp, so
/// the rule is visible without becoming a second border colour).

/// The subtitle under a page header is the first thing a large text scale
/// crowds out. Above this scale factor the title alone carries the header: the
/// page still says what it is, and nothing is clipped to say it.
const double _subtitleMaxScale = 1.45;

/// The branded compact header pushed account pages share with the rest of the
/// app: a green rounded-bottom banner with a fine golden lower edge, an
/// optional back action on the leading edge, a contextual icon, and one
/// ellipsized localized title (plus a restrained subtitle when it fits).
///
/// It is deliberately not an [AppBar]: Home, Counter and Calculator all draw
/// their own branded top treatment, and an account page pushed from any of them
/// should not suddenly look like Material chrome. It paints into the status bar
/// area itself ([MediaQuery.paddingOf] top inset), so the green reaches the top
/// edge of the screen while the back action keeps its 48 dp hit area.
class AccountPageHeader extends StatelessWidget {
  const AccountPageHeader({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.onBack,
    this.trailing,
    this.backTooltip,
  });

  /// Localized page title. Always one line, always ellipsized.
  final String title;

  /// The contextual glyph that names the page's subject.
  final IconData icon;

  /// Localized supporting line; dropped above [_subtitleMaxScale].
  final String? subtitle;

  /// Back action. `null` leaves the leading slot at its padding width, so the
  /// title keeps the same starting edge whether or not the page can pop.
  final VoidCallback? onBack;

  final String? backTooltip;

  /// Optional quiet action pinned to the trailing edge (for example the cloud
  /// screen's "new sync" style affordance). Never a second filled button.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final double topInset = media.padding.top;
    final double textScale = media.textScaler.scale(14) / 14;
    final String? support = subtitle;
    final bool showSubtitle =
        support != null && support.isNotEmpty && textScale <= _subtitleMaxScale;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: AppColors.headerGreen,
      ),
      child: LedgerHeaderBackground(
        key: const Key('account-page-header'),
        child: Padding(
          padding: EdgeInsets.fromLTRB(6, topInset + 6, 6, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              if (onBack case final VoidCallback back) ...<Widget>[
                IconButton(
                  key: const Key('account-page-back'),
                  onPressed: back,
                  tooltip: backTooltip,
                  color: AppColors.onPrimary,
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 2),
              ] else
                const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        // A quiet tinted badge so the contextual glyph reads as
                        // part of the banner, not as a loose colour accent.
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.onPrimary.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(icon, size: 17, color: AppColors.golden),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            title,
                            key: const Key('account-page-title'),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 19,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              color: AppColors.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (showSubtitle) ...<Widget>[
                      const SizedBox(height: 3),
                      Padding(
                        padding: const EdgeInsets.only(left: 37),
                        child: Text(
                          support,
                          key: const Key('account-page-subtitle'),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.25,
                            fontStyle: FontStyle.italic,
                            color: AppColors.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing case final Widget action) ...<Widget>[
                const SizedBox(width: 4),
                action,
              ] else
                const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// S11 — Optional Google Sign-in screen for cloud backup & sync (B5).
///
/// Explains clearly that cloud backup is optional and that all local khatas and
/// entries stay on this phone whether or not the user signs in. Supports
/// English and Bengali through [language] using local en/bn string pairs.
///
/// Pops with the authenticated [CloudUser] on success (and invokes
/// [onSignedIn] when supplied). Cancellation and errors keep the screen open
/// with non-blocking inline feedback.
///
/// Visual system: the shared branded page header, a hero card washed in the app
/// light green (badge, title and the green "local data stays" pill), an ivory
/// checklist of what signing in does and does not change, and one action card
/// where the Google button is the only filled control and the quiet exit is
/// outlined under it. Cards share warm surfaces, radius 20, a 1 dp beige border
/// and the single soft shadow.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.backend,
    this.language = AppLanguage.en,
    this.onSignedIn,
  });

  final CloudBackend backend;
  final AppLanguage language;
  final ValueChanged<CloudUser>? onSignedIn;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

enum _SignInFeedback { none, cancelled, offline, failed }

class _SignInScreenState extends State<SignInScreen> {
  bool _signingIn = false;
  _SignInFeedback _feedback = _SignInFeedback.none;
  String? _errorDetail;

  /// Wraps the progress or feedback panel so it can be scrolled into view: on
  /// a short screen or at a large text scale it sits below the fold.
  final GlobalKey _statusKey = GlobalKey();

  void _revealStatus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? target = _statusKey.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  bool get _bn => widget.language == AppLanguage.bn;

  String _pair(String en, String bn) => _bn ? bn : en;

  Future<void> _handleGoogleSignIn() async {
    if (_signingIn) return;
    setState(() {
      _signingIn = true;
      _feedback = _SignInFeedback.none;
      _errorDetail = null;
    });
    _revealStatus();

    try {
      final CloudUser? user = await widget.backend.signInWithGoogle();
      if (!mounted) return;
      if (user == null) {
        setState(() {
          _signingIn = false;
          _feedback = _SignInFeedback.cancelled;
        });
        _revealStatus();
        return;
      }
      setState(() {
        _signingIn = false;
      });
      widget.onSignedIn?.call(user);
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(user);
      }
    } on CloudOfflineException {
      if (!mounted) return;
      setState(() {
        _signingIn = false;
        _feedback = _SignInFeedback.offline;
      });
      _revealStatus();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _signingIn = false;
        _feedback = _SignInFeedback.failed;
        _errorDetail = _sanitizeError(error);
      });
      _revealStatus();
    }
  }

  String? _sanitizeError(Object error) {
    final String text = error
        .toString()
        .replaceFirst(RegExp(r'^(Exception|StateError|Bad state):\s*'), '')
        .trim();
    if (text.isEmpty || text.length > 140) return null;
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final bool canPop = Navigator.of(context).canPop();
    return Scaffold(
      key: const Key('sign-in-screen'),
      backgroundColor: AppColors.creamBackground,
      body: Column(
        children: <Widget>[
          AccountPageHeader(
            title: _pair('Sign in', 'সাইন ইন'),
            subtitle: _pair('Optional cloud backup', 'ঐচ্ছিক ক্লাউড ব্যাকআপ'),
            icon: Icons.cloud_outlined,
            backTooltip: _pair('Back', 'পেছনে'),
            onBack: canPop ? () => Navigator.of(context).maybePop() : null,
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: <Widget>[
                  _HeroCard(
                    title: _pair(
                      'Optional Cloud Backup',
                      'ঐচ্ছিক ক্লাউড ব্যাকআপ',
                    ),
                    // The title already says "optional"; the paragraph keeps the
                    // one promise that matters and the checklist below keeps
                    // the detail.
                    subtitle: _pair(
                      'Your khatas and entries always stay saved on this phone, even without an account or internet.',
                      'অ্যাকাউন্ট বা ইন্টারনেট ছাড়াই আপনার সব খাতা ও লেনদেন এই ফোনে সুরক্ষিত থাকে।',
                    ),
                    localBadge: _pair(
                      'Local data stays on this phone',
                      'স্থানীয় তথ্য এই ফোনেই থাকে',
                    ),
                  ),
                  const SizedBox(height: 14),
                  _BenefitsCard(
                    title: _pair('What signing in does', 'সাইন ইন করলে যা হয়'),
                    items: <String>[
                      _pair(
                        'Back up your khatas across devices when online.',
                        'অনলাইনে থাকলে খাতাগুলো ক্লাউডে ব্যাকআপ রাখুন।',
                      ),
                      _pair(
                        'Add and edit entries offline — sync catches up later.',
                        'অফলাইনে লেনদেন যোগ বা সম্পাদনা করুন — সিঙ্ক পরে নিজেই হবে।',
                      ),
                      _pair(
                        'Signing out never deletes your local khatas or entries.',
                        'লগ আউট করলেও ফোনের খাতা বা লেনদেন মুছে যায় না।',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _ActionCard(
                    signingIn: _signingIn,
                    statusKey: _statusKey,
                    pair: _pair,
                    feedback: _feedback,
                    errorDetail: _errorDetail,
                    bn: _bn,
                    onContinue: _handleGoogleSignIn,
                    onKeepLocal: canPop
                        ? () => Navigator.of(context).maybePop()
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One warm-ivory card: radius 20, one beige hairline, one soft shadow.
class _CardShell extends StatelessWidget {
  const _CardShell({super.key, required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(_accountRadius),
        border: Border.all(color: AppColors.outline),
        boxShadow: _cardShadow(),
      ),
      child: child,
    );
  }
}

/// The hero: what this screen offers, in the app's own light green, with the
/// "your data stays here" promise as a pill that cannot be missed or misread.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.localBadge,
  });

  final String title;
  final String subtitle;
  final String localBadge;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      key: const Key('sign-in-hero'),
      color: AppColors.lightGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.outline),
                ),
                child: const Icon(
                  Icons.cloud_done_outlined,
                  color: AppColors.primaryGreen,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          letterSpacing: -0.1,
                          color: AppColors.headerGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.outline),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.smartphone_outlined,
                            size: 13,
                            color: AppColors.primaryGreen,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              localBadge,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.darkText,
            ),
          ),
        ],
      ),
    );
  }
}

/// The checklist: one ivory card, one line per promise, a hairline rule between
/// lines so three statements read as a list and not as a paragraph.
class _BenefitsCard extends StatelessWidget {
  const _BenefitsCard({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1.25,
              color: AppColors.darkText,
            ),
          ),
          const SizedBox(height: 12),
          for (int index = 0; index < items.length; index++) ...<Widget>[
            if (index > 0) ...<Widget>[
              const SizedBox(height: 10),
              Divider(
                height: 1,
                thickness: 1,
                color: AppColors.outline.withValues(alpha: 0.55),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.check_circle_outline,
                    size: 17,
                    color: AppColors.greenSuccess,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    items[index],
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.darkText,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The actions: exactly one filled control (Google), one quiet outlined exit
/// under it, and the inline progress / result panel between them and the CTA.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.signingIn,
    required this.statusKey,
    required this.pair,
    required this.feedback,
    required this.errorDetail,
    required this.bn,
    required this.onContinue,
    required this.onKeepLocal,
  });

  final bool signingIn;
  final GlobalKey statusKey;
  final String Function(String en, String bn) pair;
  final _SignInFeedback feedback;
  final String? errorDetail;
  final bool bn;
  final VoidCallback onContinue;
  final VoidCallback? onKeepLocal;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FilledButton.icon(
            key: const Key('continue-with-google-button'),
            onPressed: signingIn ? null : onContinue,
            icon: signingIn
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : const Icon(Icons.account_circle_outlined),
            label: Text(
              signingIn
                  ? pair('Signing in…', 'সাইন ইন হচ্ছে…')
                  : pair('Continue with Google', 'Google দিয়ে চালিয়ে যান'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          if (signingIn) ...<Widget>[
            const SizedBox(height: 12),
            Semantics(
              key: statusKey,
              liveRegion: true,
              child: Container(
                key: const Key('sign-in-progress'),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        pair(
                          'Connecting to Google… You can keep using Khoroch Diary offline anytime.',
                          'Google-এর সাথে সংযোগ করা হচ্ছে… আপনি যেকোনো সময় অফলাইনে খরচের ডায়েরি ব্যবহার করতে পারেন।',
                        ),
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: AppColors.darkText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (feedback != _SignInFeedback.none) ...<Widget>[
            const SizedBox(height: 12),
            KeyedSubtree(
              key: statusKey,
              child: _FeedbackBanner(
                feedback: feedback,
                detail: errorDetail,
                bn: bn,
              ),
            ),
          ],
          if (onKeepLocal case final VoidCallback keepLocal) ...<Widget>[
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('sign-in-not-now-button'),
              onPressed: signingIn ? null : keepLocal,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.softText,
                side: const BorderSide(color: AppColors.outline),
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(
                pair('Keep local-only for now', 'এখন শুধু ফোনেই রাখুন'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({
    required this.feedback,
    required this.detail,
    required this.bn,
  });

  final _SignInFeedback feedback;
  final String? detail;
  final bool bn;

  String _pair(String en, String bnText) => bn ? bnText : en;

  @override
  Widget build(BuildContext context) {
    final bool isCancel = feedback == _SignInFeedback.cancelled;
    final String heading = switch (feedback) {
      _SignInFeedback.cancelled => _pair(
        'Sign-in cancelled. Your local data is untouched.',
        'সাইন ইন বাতিল করা হয়েছে। আপনার ফোনের তথ্য অক্ষত আছে।',
      ),
      _SignInFeedback.offline => _pair(
        'You appear to be offline. Connect to the internet and try again.',
        'ইন্টারনেট সংযোগ নেই। অনলাইনে এসে আবার চেষ্টা করুন।',
      ),
      _SignInFeedback.failed => _pair(
        'Could not sign in with Google. Please try again.',
        'Google দিয়ে সাইন ইন করা যায়নি। অনুগ্রহ করে আবার চেষ্টা করুন।',
      ),
      _SignInFeedback.none => '',
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('sign-in-feedback'),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: isCancel ? AppColors.lightGreen : AppColors.warmIvory,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCancel ? AppColors.outline : AppColors.expenseRed,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              isCancel ? Icons.info_outline : Icons.error_outline,
              color: isCancel ? AppColors.primaryGreen : AppColors.expenseRed,
              size: 19,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    heading,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                      color: AppColors.darkText,
                    ),
                  ),
                  if (!isCancel)
                    if (detail case final String errorText) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        errorText,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppColors.softText,
                        ),
                      ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
