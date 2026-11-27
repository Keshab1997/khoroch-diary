import 'dart:async' show unawaited;

import 'package:app_pulse_kit/app_pulse_kit.dart';
// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:smart_review_feedback/smart_review_feedback.dart';

import '../../core/config/pulse_config.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ledger_header_background.dart';

/// The single soft card shadow from `theme.md` (blur 14, offset 0/4), shared
/// across the Profile and App Settings panels so every surface matches.
List<BoxShadow> accountCardShadow() => <BoxShadow>[
  BoxShadow(
    color: AppColors.darkText.withValues(alpha: 0.05),
    blurRadius: 14,
    offset: const Offset(0, 4),
  ),
];

/// The caller owns the committed language. Return true only once the change
/// succeeds, false on cancellation, or throw on failure. Update [SettingsScreen.language]
/// from the caller after success; this screen does not write to storage.
///
/// Layout: the account-family header shared with Profile - the compact green
/// banner with the rounded bottom edge and the 3 dp golden rule from the
/// Counter's reference treatment - then `Preferences` and `Storage` panels
/// (radius 20, 1 dp beige border, one soft shadow) with clear panel headings.
/// Every row uses the shared [AccountRow] primitive so titles and subtitles
/// take the full remaining width while value/status chips wrap cleanly below.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.language = AppLanguage.en,
    this.onLanguageChanged,
    this.pulseController,
    this.reviewController,
  });

  final AppLanguage language;
  final Future<bool> Function(AppLanguage)? onLanguageChanged;
  final AppPulseController? pulseController;
  final SmartReviewController? reviewController;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _picking = false;
  bool _busy = false;
  bool _failed = false;
  int _buildTapCount = 0;

  void _handleBuildTap(AppPulseController? pulse) {
    if (pulse == null) return;
    _buildTapCount++;
    if (_buildTapCount >= 5) {
      _buildTapCount = 0;
      unawaited(PulseDebugSheet.show(context, controller: pulse));
    }
  }

  Future<void> _chooseLanguage(AppStrings strings) async {
    if (_picking || _busy || kIsWeb || widget.onLanguageChanged == null) return;
    _picking = true;
    final AppLanguage? choice = await showDialog<AppLanguage>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: Text(strings.text(AppString.changeLanguage)),
        children: <Widget>[
          for (final AppLanguage language in AppLanguage.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, language),
              child: Row(
                children: <Widget>[
                  Icon(
                    widget.language == language
                        ? Icons.check_circle
                        : Icons.circle,
                    size: 20,
                    color: AppColors.primaryGreen,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      selected: widget.language == language,
                      child: Text(language.endonym),
                    ),
                  ),
                ],
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(strings.text(AppString.cancel)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _picking = false;
    final Future<bool> Function(AppLanguage)? callback =
        widget.onLanguageChanged;
    if (choice == null || choice == widget.language || callback == null) {
      return;
    }

    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      // A false result is cancellation. The committed value belongs to the
      // caller, so neither cancellation nor success is optimistic here.
      await callback(choice);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings(widget.language);
    final String Function(AppString) text = strings.text;
    final bool canChoose = widget.onLanguageChanged != null;
    final String subtitle = text(AppString.settingsDescription);
    if (kIsWeb) {
      return Scaffold(
        body: Column(
          children: <Widget>[
            AccountPageHeader(
              key: const Key('settings-header'),
              title: text(AppString.appSettings),
              subtitle: subtitle,
              icon: Icons.settings_outlined,
              leading: const _HeaderBackButton(),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: AccountSurfaceCard(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const AccountIconBadge(
                            icon: Icons.info_outline,
                            size: 52,
                            radius: 16,
                            iconSize: 26,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            text(AppString.webSettings),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: AppColors.softText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      key: const Key('settings-screen'),
      body: Column(
        children: <Widget>[
          AccountPageHeader(
            key: const Key('settings-header'),
            title: text(AppString.appSettings),
            subtitle: subtitle,
            icon: Icons.settings_outlined,
            leading: const _HeaderBackButton(),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: <Widget>[
                  AccountSectionPanel(
                    heading: text(AppString.preferences),
                    children: <Widget>[
                      AccountRow(
                        key: const Key('settings-currency-row'),
                        icon: Icons.currency_rupee,
                        title: text(AppString.currency),
                        subtitle: text(AppString.currencyDetail),
                        value: text(AppString.currencyInr),
                        mergeReadOnlySemantics: true,
                      ),
                      const AccountRowDivider(),
                      AccountRow(
                        key: const Key('settings-theme-row'),
                        icon: Icons.light_mode_outlined,
                        title: text(AppString.theme),
                        subtitle: text(AppString.themeDetail),
                        value: text(AppString.light),
                        mergeReadOnlySemantics: true,
                      ),
                      const AccountRowDivider(),
                      AccountRow(
                        key: const Key('settings-language-row'),
                        icon: Icons.translate_outlined,
                        title: text(AppString.language),
                        subtitle: text(
                          canChoose
                              ? AppString.languageDetail
                              : AppString.languageUnavailable,
                        ),
                        value: widget.language.endonym,
                        status: canChoose ? null : text(AppString.notAvailable),
                        mergeReadOnlySemantics: true,
                      ),
                      if (canChoose) ...<Widget>[
                        const AccountRowDivider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              OutlinedButton.icon(
                                key: const Key('settings-change-language'),
                                onPressed: _busy
                                    ? null
                                    : () => _chooseLanguage(strings),
                                icon: const Icon(
                                  Icons.translate_outlined,
                                  size: 18,
                                ),
                                label: Text(text(AppString.changeLanguage)),
                              ),
                              if (_busy || _failed)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Icon(
                                          _busy
                                              ? Icons.sync
                                              : Icons.error_outline,
                                          size: 16,
                                          color: _busy
                                              ? AppColors.primaryGreen
                                              : AppColors.expenseRed,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            text(
                                              _busy
                                                  ? AppString.languagePending
                                                  : AppString.languageFailed,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              height: 1.35,
                                              color: AppColors.darkText,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  AccountSectionPanel(
                    heading: text(AppString.storage),
                    children: <Widget>[
                      AccountRow(
                        key: const Key('settings-storage-row'),
                        icon: Icons.smartphone_outlined,
                        title: text(AppString.storageTitle),
                        subtitle: text(AppString.storageDetail),
                        value: text(AppString.thisDevice),
                        mergeReadOnlySemantics: true,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(66, 0, 14, 12),
                        child: Text(
                          text(AppString.settingsBackupHint),
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: AppColors.softText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  ..._buildStudioSections(context),
                  const SizedBox(height: 14),
                  Center(
                    child: GestureDetector(
                      onTap: () => _handleBuildTap(
                        widget.pulseController ??
                            KhorochServicesScope.maybeOf(context)
                                ?.pulseController,
                      ),
                      child: Text(
                        strings.buildLabel('1.0.0', 1),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.softText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStudioSections(BuildContext context) {
    final KhorochServicesScope? scope = KhorochServicesScope.maybeOf(context);
    final AppPulseController? pulse =
        widget.pulseController ?? scope?.pulseController;
    final SmartReviewController? review =
        widget.reviewController ?? scope?.reviewController;
    if (pulse == null && review == null) return const <Widget>[];

    final bool bn = widget.language == AppLanguage.bn;
    return <Widget>[
      const SizedBox(height: 12),
      AccountSectionPanel(
        heading: bn ? 'অ্যাপ ও মতামত' : 'App & Feedback',
        children: <Widget>[
          if (review != null)
            AccountRow(
              key: const Key('settings-rate-feedback-row'),
              icon: Icons.star_rate_rounded,
              title: bn ? 'রেটিং ও মতামত' : 'Rate & Feedback',
              subtitle: bn
                  ? 'অ্যাপটি কেমন লাগছে জানান বা সমস্যা রিপোর্ট করুন।'
                  : 'Share a rating or send private feedback.',
              onTap: () {
                unawaited(
                  review.showNow(
                    context,
                    strings: bn
                        ? const ReviewStrings.bn(
                            appName: KhorochPulseConfig.appName,
                          )
                        : const ReviewStrings.en(
                            appName: KhorochPulseConfig.appName,
                          ),
                    screenName: 'SettingsScreen',
                  ),
                );
              },
            ),
          if (review != null && pulse != null) const AccountRowDivider(),
          if (pulse != null)
            AccountRow(
              key: const Key('settings-check-updates-row'),
              icon: Icons.system_update_outlined,
              title: bn ? 'আপডেট চেক করুন' : 'Check for updates',
              subtitle: bn
                  ? 'নতুন ভার্সন বা জরুরি ঘোষণা আছে কিনা দেখুন।'
                  : 'Check for the latest version or notices.',
              onTap: () {
                unawaited(pulse.refresh());
              },
            ),
        ],
      ),
    ];
  }
}

/// The account-family header shared between Profile and App Settings: the
/// compact green banner with the rounded bottom edge and the 3 dp golden rule
/// from the Counter's reference treatment, carrying a circular golden badge,
/// the screen title, one restrained line of context, and an optional 48 dp
/// leading or trailing control.
class AccountPageHeader extends StatelessWidget {
  const AccountPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.leading,
    this.action,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? leading;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final double topInset = MediaQuery.viewPaddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: AppColors.headerGreen,
      ),
      child: LedgerHeaderBackground(
        child: Padding(
          padding: EdgeInsets.only(
            top: topInset + 10,
            left: 12,
            right: 12,
            bottom: 25,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: <Widget>[
                if (leading != null) ...<Widget>[
                  SizedBox(width: 48, height: 48, child: leading),
                  const SizedBox(width: 2),
                ],
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: AppColors.golden,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 24, color: AppColors.headerGreen),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.onPrimary,
                            height: 1.15,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: AppColors.onPrimary.withValues(alpha: 0.85),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ?action,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A real [BackButton] in a 48 dp box: unchanged runtime type and semantics
/// for the existing navigation tests, larger than the default target.
class _HeaderBackButton extends StatelessWidget {
  const _HeaderBackButton();

  @override
  Widget build(BuildContext context) {
    // Like an AppBar, the control only exists when there is something to pop,
    // so a standalone Settings route offers no dead tap.
    if (!Navigator.of(context).canPop()) return const SizedBox.shrink();
    return SizedBox(
      width: 48,
      height: 48,
      child: BackButton(
        color: AppColors.onPrimary,
        onPressed: () => Navigator.maybePop(context),
      ),
    );
  }
}

/// Rounded warm-ivory surface with the 1 dp beige border and one soft shadow.
class AccountSurfaceCard extends StatelessWidget {
  const AccountSurfaceCard({super.key, required this.child, this.background});

  final Widget child;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: background ?? AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
        boxShadow: accountCardShadow(),
      ),
      child: child,
    );
  }
}

/// Grouped panel shared by Profile and Settings: a warm-ivory card with a
/// tinted header band (4 dp green rule + bold group heading) and a Material
/// surface so enabled rows ripple cleanly while read-only rows stay inert.
class AccountSectionPanel extends StatelessWidget {
  const AccountSectionPanel({
    super.key,
    required this.heading,
    required this.children,
  });

  final String heading;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: accountCardShadow(),
      ),
      child: Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.lightGreen.withValues(alpha: 0.55),
                border: const Border(
                  bottom: BorderSide(color: AppColors.outline),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Container(
                      width: 4,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      heading,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.darkText,
                        letterSpacing: 0.2,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Hairline rule between adjacent [AccountRow] items inside a panel.
class AccountRowDivider extends StatelessWidget {
  const AccountRowDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      indent: 66,
      endIndent: 14,
      color: AppColors.outline,
    );
  }
}

/// Rounded-square icon tile shared by every Profile and Settings row.
class AccountIconBadge extends StatelessWidget {
  const AccountIconBadge({
    super.key,
    required this.icon,
    this.enabled = true,
    this.destructive = false,
    this.size = 40,
    this.radius = 12,
    this.iconSize = 20,
    this.background,
  });

  final IconData icon;
  final bool enabled;
  final bool destructive;
  final double size;
  final double radius;
  final double iconSize;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final Color fillColor =
        background ??
        (destructive
            ? AppColors.expenseRed.withValues(alpha: enabled ? 0.14 : 0.08)
            : (enabled
                  ? AppColors.lightGreen
                  : AppColors.beige.withValues(alpha: 0.45)));
    final Color fgColor = destructive
        ? (enabled
              ? AppColors.expenseRed
              : AppColors.expenseRed.withValues(alpha: 0.75))
        : (enabled ? AppColors.primaryGreen : AppColors.softText);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, size: iconSize, color: fgColor),
    );
  }
}

/// Value or status pill shared across Profile and Settings. Text wraps inside
/// the capsule so long Bengali labels at 200% text never overflow.
class AccountStatusChip extends StatelessWidget {
  const AccountStatusChip({
    super.key,
    required this.label,
    this.highlighted = false,
  });

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.lightGreen : AppColors.creamBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.outline),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: highlighted ? AppColors.primaryGreen : AppColors.softText,
        ),
      ),
    );
  }
}

/// Shared long-text-safe row primitive used once across Profile and Settings.
///
/// Layout guarantees at narrow widths (320 dp) and large text (`textScaler` 2.0):
///   * The 40 dp leading icon tile sits at `CrossAxisAlignment.start` so it
///     stays aligned with the first line rather than floating in the vertical
///     middle of a tall wrapped row.
///   * When [onTap] is non-null, the trailing chevron shares only the first-line
///     header [Row] with `CrossAxisAlignment.start`, keeping it anchored to the
///     first line while [subtitle] and value/status chips span the full
///     remaining column width underneath.
///   * Value and status badges wrap below the text copy so they never squeeze
///     [title] onto one word per line.
class AccountRow extends StatelessWidget {
  const AccountRow({
    super.key,
    required this.icon,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.subtitleMaxLines,
    this.value,
    this.status,
    this.onTap,
    this.destructive = false,
    this.mergeReadOnlySemantics = false,
  });

  final IconData icon;
  final String title;
  final String? eyebrow;
  final String? subtitle;
  final int? subtitleMaxLines;
  final String? value;
  final String? status;
  final VoidCallback? onTap;
  final bool destructive;
  final bool mergeReadOnlySemantics;

  @override
  Widget build(BuildContext context) {
    final bool available = onTap != null;
    final bool activeBadge = available || value != null || eyebrow != null;
    final double verticalPadding = eyebrow != null && subtitle == null
        ? 11
        : 13;

    final Widget content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: eyebrow != null ? 48 : 56),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: verticalPadding,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AccountIconBadge(
              icon: icon,
              enabled: activeBadge,
              destructive: destructive,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (eyebrow != null) ...<Widget>[
                    Text(
                      eyebrow!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.softText,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: destructive && available
                                  ? AppColors.expenseRed
                                  : AppColors.darkText,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ),
                      if (available) ...<Widget>[
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.chevron_right,
                            size: 22,
                            color: destructive
                                ? AppColors.expenseRed
                                : AppColors.primaryGreen,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: subtitleMaxLines,
                      overflow: subtitleMaxLines != null
                          ? TextOverflow.ellipsis
                          : null,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.softText,
                      ),
                    ),
                  ],
                  if (value != null || status != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        if (value != null)
                          AccountStatusChip(label: value!, highlighted: true),
                        if (status != null) AccountStatusChip(label: status!),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (available) {
      return InkWell(onTap: onTap, child: content);
    }
    if (mergeReadOnlySemantics) {
      return Semantics(
        container: true,
        label: <String>[?eyebrow, title, ?value, ?status, ?subtitle].join('. '),
        child: ExcludeSemantics(child: content),
      );
    }
    return content;
  }
}
