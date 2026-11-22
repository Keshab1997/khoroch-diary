// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/l10n/app_strings.dart' show AppLanguage;
import '../../core/theme/app_colors.dart';
import 'sync_engine.dart';
import 'sync_status.dart';

/// The single soft card shadow from `theme.md` (blur 14, offset 0/4).
List<BoxShadow> _cardShadow() => <BoxShadow>[
  BoxShadow(
    color: AppColors.darkText.withValues(alpha: 0.05),
    blurRadius: 14,
    offset: const Offset(0, 4),
  ),
];

/// Self-contained Cloud Account & Backup card for Profile (S5, B5).
///
/// Renders all four S5 sync states without ever showing a blocking modal
/// progress dialog:
/// * **local-only** (`SyncStateKind.signedOut`) — `Not signed in` status pill,
///   hint *"Sign in to enable cloud backup"* and a **Sign in** button;
/// * **signed in** (`SyncStateKind.idle`) — email, a crisp green status pill
///   (`Up to date` / `Waiting to sync`), `Last synced …`, `N pending`,
///   **Back up now**, and **Log out** in [AppColors.expenseRed] behind a
///   confirmation dialog;
/// * **syncing** (`SyncStateKind.syncing`) — a calm `lightGreen` panel with the
///   state text and the reassurance that the app stays usable: nothing on the
///   card animates or blocks, so the screen is never a waiting room;
/// * **error** (`SyncStateKind.error`) — red status pill, failure reason,
///   `N pending`, **Retry** and **Log out**.
///
/// Backing up while offline is a no-op that shows a clear inline message.
/// Logging out never deletes local data. Every colour comes from [AppColors].
class AccountCard extends StatefulWidget {
  const AccountCard({
    super.key,
    this.status,
    this.statusStream,
    this.language = AppLanguage.en,
    this.onSignIn,
    this.onBackupNow,
    this.onRetry,
    this.onConfirmAccountSwitch,
    this.onSignOut,
    this.isOnline,
  });

  /// Direct status snapshot (useful for stateless parents and widget tests).
  final SyncStatus? status;

  /// Optional live stream of [SyncStatus] updates (e.g. [SyncEngine.statusStream]).
  final Stream<SyncStatus>? statusStream;

  /// Display language (`en` or `bn`).
  final AppLanguage language;

  /// Invoked when the user taps **Sign in** in local-only mode.
  final VoidCallback? onSignIn;

  /// Invoked when the user taps **Back up now**. May optionally return a
  /// [SyncOutcome] so offline results automatically surface the offline notice.
  final Future<SyncOutcome?> Function()? onBackupNow;

  /// Invoked when the user taps **Retry** in the error state. Falls back to
  /// [onBackupNow] when omitted.
  final Future<SyncOutcome?> Function()? onRetry;

  /// Invoked when a different account signed in than the one this device last
  /// synced with and the user confirms syncing with the new account.
  final Future<SyncOutcome?> Function()? onConfirmAccountSwitch;

  /// Invoked after the user confirms **Log out**. Never deletes local data.
  final Future<void> Function()? onSignOut;

  /// Optional connectivity check checked before running [onBackupNow] or
  /// [onRetry]. When it returns `false`, backup does nothing and displays an
  /// inline offline notice.
  final Future<bool> Function()? isOnline;

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  bool _offlineNotice = false;
  bool _busyAction = false;

  bool get _bn => widget.language == AppLanguage.bn;

  String _pair(String en, String bn) => _bn ? bn : en;

  String _digits(String input) {
    if (!_bn) return input;
    return input.replaceAllMapped(
      RegExp('[0-9]'),
      (Match m) => '০১২৩৪৫৬৭৮৯'[int.parse(m[0]!)],
    );
  }

  String _pendingLabel(int count) {
    final String n = _digits(count.toString());
    return _bn ? '$nটি অপেক্ষমাণ' : '$n pending';
  }

  String _lastSyncedLabel(DateTime? lastSyncedAt) {
    if (lastSyncedAt == null) {
      return _pair('Last synced: Never', 'সর্বশেষ সিঙ্ক: কখনও নয়');
    }
    final DateTime local = lastSyncedAt.toLocal();
    if (!_bn) {
      return 'Last synced ${formatEntryDate(local)}';
    }
    const List<String> bnMonths = <String>[
      'জানু',
      'ফেব্রু',
      'মার্চ',
      'এপ্রিল',
      'মে',
      'জুন',
      'জুলাই',
      'আগস্ট',
      'সেপ্টে',
      'অক্টো',
      'নভে',
      'ডিসে',
    ];
    final String day = _digits(local.day.toString().padLeft(2, '0'));
    final String month = bnMonths[local.month - 1];
    final String year = _digits(local.year.toString());
    final int hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final String minute = _digits(local.minute.toString().padLeft(2, '0'));
    final String marker = local.hour < 12 ? 'পূর্বাহ্ণ' : 'অপরাহ্ণ';
    final String hourText = _digits(hour12.toString());
    return 'সর্বশেষ সিঙ্ক $day $month $year, $hourText:$minute $marker';
  }

  Future<void> _runBackupAction(
    Future<SyncOutcome?> Function()? callback,
  ) async {
    if (_busyAction) return;
    if (widget.isOnline != null) {
      bool online = true;
      try {
        online = await widget.isOnline!();
      } catch (_) {
        online = false;
      }
      if (!online) {
        if (mounted) {
          setState(() => _offlineNotice = true);
        }
        return;
      }
    }

    if (callback == null) return;
    setState(() {
      _busyAction = true;
      _offlineNotice = false;
    });
    try {
      final SyncOutcome? outcome = await callback();
      if (!mounted) return;
      setState(() {
        _busyAction = false;
        _offlineNotice = outcome == SyncOutcome.offline;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busyAction = false);
    }
  }

  Future<void> _confirmAndSignOut() async {
    if (_busyAction || widget.onSignOut == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Row(
            children: <Widget>[
              const Icon(Icons.logout, size: 22, color: AppColors.expenseRed),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _pair('Log out?', 'লগ আউট করবেন?'),
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              _pair(
                'You will stop syncing to the cloud. Your local khatas and transactions on this device will NOT be deleted.',
                'ক্লাউডে সিঙ্ক বন্ধ হয়ে যাবে। এই ফোনে থাকা আপনার খাতা ও লেনদেন মুছে যাবে না।',
              ),
              style: const TextStyle(color: AppColors.darkText, height: 1.4),
            ),
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('account-logout-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
              ),
              child: Text(_pair('Cancel', 'বাতিল করুন')),
            ),
            TextButton(
              key: const Key('account-logout-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.expenseRed,
              ),
              child: Text(
                _pair('Log out', 'লগ আউট'),
                style: const TextStyle(
                  color: AppColors.expenseRed,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      _busyAction = true;
      _offlineNotice = false;
    });
    try {
      await widget.onSignOut!();
    } finally {
      if (mounted) {
        setState(() => _busyAction = false);
      }
    }
  }

  Future<void> _confirmAccountSwitch() async {
    if (_busyAction || widget.onConfirmAccountSwitch == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Row(
            children: <Widget>[
              const Icon(
                Icons.swap_horiz_outlined,
                size: 22,
                color: AppColors.primaryGreen,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _pair(
                    'Sync with this Google account?',
                    'এই Google অ্যাকাউন্টে সিঙ্ক করবেন?',
                  ),
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              _pair(
                'This device previously synced with a different account. Confirming will sync all local khatas and entries on this phone with the new account.',
                'এই ফোনটি আগে অন্য একটি অ্যাকাউন্টের সাথে সিঙ্ক করা হয়েছিল। নিশ্চিত করলে ফোনের সব খাতা ও লেনদেন নতুন অ্যাকাউন্টের সাথে সিঙ্ক হবে।',
              ),
              style: const TextStyle(color: AppColors.darkText, height: 1.4),
            ),
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('account-switch-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(foregroundColor: AppColors.softText),
              child: Text(_pair('Cancel', 'বাতিল করুন')),
            ),
            FilledButton(
              key: const Key('account-switch-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_pair('Confirm & Sync', 'নিশ্চিত করুন ও সিঙ্ক করুন')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await _runBackupAction(widget.onConfirmAccountSwitch);
  }

  @override
  Widget build(BuildContext context) {
    final Stream<SyncStatus>? stream = widget.statusStream;
    final SyncStatus fallback = widget.status ?? const SyncStatus.signedOut();
    if (stream == null) {
      return _buildCard(context, fallback);
    }
    return StreamBuilder<SyncStatus>(
      stream: stream,
      initialData: widget.status,
      builder: (BuildContext context, AsyncSnapshot<SyncStatus> snapshot) {
        return _buildCard(context, snapshot.data ?? fallback);
      },
    );
  }

  Widget _buildCard(BuildContext context, SyncStatus current) {
    final bool showOffline = _offlineNotice || current.isOffline;

    return Container(
      key: const Key('account-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
        boxShadow: _cardShadow(),
      ),
      child: switch (current.kind) {
        SyncStateKind.signedOut => _buildSignedOut(),
        SyncStateKind.syncing => _buildSyncing(current),
        SyncStateKind.error => _buildError(current, showOffline: showOffline),
        SyncStateKind.idle => _buildSignedInIdle(
          current,
          showOffline: showOffline,
        ),
      },
    );
  }

  Widget _buildSignedOut() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _CardLabel(text: _pair('Cloud account', 'ক্লাউড অ্যাকাউন্ট')),
        const SizedBox(height: 10),
        _CardHeader(
          badge: const _LeadingBadge(
            icon: Icons.cloud_off_outlined,
            iconColor: AppColors.softText,
            backgroundColor: AppColors.creamBackground,
          ),
          title: _pair('Local-only mode', 'শুধু ফোনে সংরক্ষিত'),
          pill: _StatusPill(
            label: _pair('Not signed in', 'সাইন ইন করা হয়নি'),
            color: AppColors.softText,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _pair(
            'Sign in to enable cloud backup',
            'ক্লাউড ব্যাকআপ চালু করতে সাইন ইন করুন',
          ),
          key: const Key('account-card-signin-hint'),
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            color: AppColors.softText,
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const Key('account-card-signin-button'),
          onPressed: widget.onSignIn,
          icon: const Icon(Icons.login_outlined),
          label: Text(_pair('Sign in', 'সাইন ইন করুন')),
        ),
      ],
    );
  }

  Widget _buildSignedInIdle(SyncStatus current, {required bool showOffline}) {
    final String email =
        current.userEmail ?? _pair('Signed in', 'সাইন ইন করা আছে');
    final bool upToDate = current.pendingCount == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _CardLabel(text: _pair('Cloud account', 'ক্লাউড অ্যাকাউন্ট')),
        const SizedBox(height: 10),
        _CardHeader(
          badge: const _LeadingBadge(
            icon: Icons.cloud_done_outlined,
            iconColor: AppColors.primaryGreen,
            backgroundColor: AppColors.lightGreen,
          ),
          title: email,
          titleKey: const Key('account-card-email'),
          pill: _StatusPill(
            label: upToDate
                ? _pair('Up to date', 'সিঙ্ক সম্পন্ন')
                : _pair('Waiting to sync', 'সিঙ্ক বাকি'),
            color: upToDate ? AppColors.greenSuccess : AppColors.softText,
          ),
        ),
        const SizedBox(height: 12),
        // Last synced and what is still waiting are one fact about the same
        // account, so they share one quiet panel instead of two loose lines.
        _FactPanel(
          key: const Key('account-card-sync-facts'),
          children: <Widget>[
            _MetaRow(
              icon: Icons.history,
              text: _lastSyncedLabel(current.lastSyncedAt),
              textKey: const Key('account-card-last-synced'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _PendingChip(label: _pendingLabel(current.pendingCount)),
            ),
          ],
        ),
        if (current.requiresAccountSwitchConfirmation) ...<Widget>[
          const SizedBox(height: 12),
          _InlineNotice(
            key: const Key('account-card-switch-warning'),
            icon: Icons.swap_horiz_outlined,
            accentColor: AppColors.primaryGreen,
            message: _pair(
              'A different account previously synced on this phone. Confirm before pushing local data.',
              'এই ফোনে আগে অন্য একটি অ্যাকাউন্ট সিঙ্ক করা ছিল। তথ্য পাঠানোর আগে নিশ্চিত করুন।',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('account-card-confirm-switch-button'),
            onPressed: _busyAction ? null : _confirmAccountSwitch,
            icon: const Icon(Icons.swap_horiz_outlined),
            label: Text(
              _pair('Confirm & Back up now', 'নিশ্চিত করুন ও এখন ব্যাকআপ নিন'),
            ),
          ),
        ] else ...<Widget>[
          if (showOffline) ...<Widget>[
            const SizedBox(height: 12),
            _InlineNotice(
              key: const Key('account-card-offline-message'),
              icon: Icons.wifi_off_outlined,
              accentColor: AppColors.softText,
              message: _pair(
                'You are offline. Connect to the internet to back up now; your local entries are safe.',
                'আপনি অফলাইনে আছেন। এখন ব্যাকআপ নিতে ইন্টারনেটে যুক্ত হোন; আপনার ফোনের লেনদেন নিরাপদ আছে।',
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('account-card-backup-button'),
            onPressed: _busyAction
                ? null
                : () => _runBackupAction(widget.onBackupNow),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(_pair('Back up now', 'এখন ব্যাকআপ নিন')),
          ),
        ],
        if (_busyAction) ...<Widget>[
          const SizedBox(height: 10),
          _WorkingNote(label: _pair('Working…', 'কাজ চলছে…')),
        ],
        const SizedBox(height: 10),
        _buildLogoutButton(),
      ],
    );
  }

  Widget _buildSyncing(SyncStatus current) {
    final String? email = current.userEmail;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CardLabel(text: _pair('Cloud account', 'ক্লাউড অ্যাকাউন্ট')),
          const SizedBox(height: 10),
          _CardHeader(
            badge: const _LeadingBadge(
              icon: Icons.sync,
              iconColor: AppColors.primaryGreen,
              backgroundColor: AppColors.lightGreen,
            ),
            title: email,
            titleKey: email == null ? null : const Key('account-card-email'),
            pill: _StatusPill(
              label: _pair('Syncing', 'সিঙ্ক হচ্ছে'),
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(height: 12),
          // A static panel, not a spinner: the card states what is happening
          // and stays readable while it happens.
          Container(
            key: const Key('account-card-syncing-panel'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.sync,
                    size: 18,
                    color: AppColors.primaryGreen,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _pair(
                          'Syncing with cloud backup…',
                          'ক্লাউড ব্যাকআপের সাথে সিঙ্ক হচ্ছে…',
                        ),
                        key: const Key('account-card-syncing-text'),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _pair(
                          'You can continue using Khoroch Diary normally.',
                          'আপনি স্বাভাবিকভাবেই খরচের ডায়েরি ব্যবহার চালিয়ে যেতে পারেন।',
                        ),
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: AppColors.softText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (current.pendingCount > 0) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _PendingChip(label: _pendingLabel(current.pendingCount)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError(SyncStatus current, {required bool showOffline}) {
    final String? email = current.userEmail;
    final String reason =
        current.errorReason ??
        _pair('Could not complete cloud sync.', 'ক্লাউড সিঙ্ক সম্পন্ন হয়নি।');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _CardLabel(text: _pair('Cloud account', 'ক্লাউড অ্যাকাউন্ট')),
        const SizedBox(height: 10),
        _CardHeader(
          badge: const _LeadingBadge(
            icon: Icons.error_outline,
            iconColor: AppColors.expenseRed,
            backgroundColor: AppColors.creamBackground,
            borderColor: AppColors.expenseRed,
          ),
          title: email,
          titleKey: email == null ? null : const Key('account-card-email'),
          pill: _StatusPill(
            label: _pair('Sync failed', 'সিঙ্ক ব্যর্থ হয়েছে'),
            color: AppColors.expenseRed,
            filled: true,
          ),
        ),
        const SizedBox(height: 12),
        // The failure reason gets its own warm surface with the red edge: it is
        // the one line on this card the user may have to act on.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.creamBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.expenseRed.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                reason,
                key: const Key('account-card-error-reason'),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.darkText,
                ),
              ),
              const SizedBox(height: 8),
              _PendingChip(label: _pendingLabel(current.pendingCount)),
            ],
          ),
        ),
        if (showOffline) ...<Widget>[
          const SizedBox(height: 12),
          _InlineNotice(
            key: const Key('account-card-offline-message'),
            icon: Icons.wifi_off_outlined,
            accentColor: AppColors.softText,
            message: _pair(
              'You are offline. Connect to the internet to retry; your local entries are safe.',
              'আপনি অফলাইনে আছেন। আবার চেষ্টা করতে ইন্টারনেটে যুক্ত হোন; আপনার ফোনের লেনদেন নিরাপদ আছে।',
            ),
          ),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const Key('account-card-retry-button'),
          onPressed: _busyAction
              ? null
              : () => _runBackupAction(widget.onRetry ?? widget.onBackupNow),
          icon: const Icon(Icons.refresh),
          label: Text(_pair('Retry', 'আবার চেষ্টা করুন')),
        ),
        if (_busyAction) ...<Widget>[
          const SizedBox(height: 10),
          _WorkingNote(label: _pair('Working…', 'কাজ চলছে…')),
        ],
        const SizedBox(height: 10),
        _buildLogoutButton(),
      ],
    );
  }

  Widget _buildLogoutButton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 14),
        Divider(
          height: 1,
          thickness: 1,
          color: AppColors.outline.withValues(alpha: 0.55),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('account-card-logout-button'),
          onPressed: _busyAction || widget.onSignOut == null
              ? null
              : _confirmAndSignOut,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.expenseRed,
            minimumSize: const Size.fromHeight(48),
            side: const BorderSide(color: AppColors.expenseRed),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
          icon: const Icon(Icons.logout, color: AppColors.expenseRed),
          label: Text(
            _pair('Log out', 'লগ আউট'),
            style: const TextStyle(
              color: AppColors.expenseRed,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// The small uppercase label that opens every state of the card.
///
/// It names what the card is for before it says what the state is, so a
/// local-only and a signed-in card are read as two states of one object rather
/// than as two unrelated panels.
class _CardLabel extends StatelessWidget {
  const _CardLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      key: const Key('account-card-label'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 11,
        height: 1.2,
        letterSpacing: 0.7,
        fontWeight: FontWeight.w800,
        color: AppColors.primaryGreen,
      ),
    );
  }
}

/// A quiet inset panel that groups the read-only facts of the signed-in state.
///
/// One cream surface with a beige hairline keeps "last synced" and "N pending"
/// together, so the card has one block of detail and not two stray lines.
class _FactPanel extends StatelessWidget {
  const _FactPanel({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.creamBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// Badge + title + state pill, the shared top line of every state.
///
/// The title is omitted when there is nothing true to say (a failed sync with
/// no account e-mail): the pill already names the state, so an empty text node
/// would only add noise.
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.badge,
    required this.title,
    required this.pill,
    this.titleKey,
  });

  final Widget badge;
  final String? title;
  final Key? titleKey;
  final Widget pill;

  @override
  Widget build(BuildContext context) {
    final String? heading = title;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        badge,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (heading != null) ...<Widget>[
                Text(
                  heading,
                  key: titleKey,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.darkText,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              pill,
            ],
          ),
        ),
      ],
    );
  }
}

/// A static "an action is running" line.
///
/// No spinner: the card stays readable and nothing on screen animates while
/// a backup is in flight, so the user can keep reading their state.
class _WorkingNote extends StatelessWidget {
  const _WorkingNote({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.sync, size: 15, color: AppColors.softText),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.softText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One read-only meta line: small octicon-style glyph plus text.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text, this.textKey});

  final IconData icon;
  final String text;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: AppColors.softText),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            key: textKey,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.softText,
            ),
          ),
        ),
      ],
    );
  }
}

class _LeadingBadge extends StatelessWidget {
  const _LeadingBadge({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    this.borderColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final Color? stroke = borderColor;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: stroke == null ? null : Border.all(color: stroke),
      ),
      child: Icon(icon, size: 22, color: iconColor),
    );
  }
}

/// The crisp sync indicator: a coloured dot plus a short state word.
class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    this.filled = false,
  });

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    // A single chip: it hugs its text and ellipsizes inside itself, so a long
    // localized state word at 200 % never forces the card wider than the phone.
    return Container(
      key: const Key('account-card-status-pill'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: filled
            ? AppColors.creamBackground
            : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: filled ? color : color.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingChip extends StatelessWidget {
  const _PendingChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('account-card-pending-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.sync, size: 13, color: AppColors.primaryGreen),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
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
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    super.key,
    required this.icon,
    required this.accentColor,
    required this.message,
  });

  final IconData icon;
  final Color accentColor;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.creamBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 18, color: accentColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
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
    );
  }
}
