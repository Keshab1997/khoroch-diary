// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ledger_header_background.dart';
import '../entry/category_artwork.dart';
import '../entry/category_picker.dart';
import '../entry/category_store.dart';
import 'models.dart';

/// Geometry shared by every card on this screen: one radius and one hairline
/// tone, so the hero, the two tiles, the empty state and the recent list all
/// belong to the same family of surfaces.
const double _cardRadius = 20;

/// The quiet 1 px rule between rows, and the two border tones: a settled one
/// for a real card and a softer one for a placeholder that has nothing in it.
const double _separator = 1;
const double _edge = 0.85;
const double _softEdge = 0.6;

/// Row geometry, so the rule between rows starts where their text starts.
const double _rowPadding = 12;
const double _avatarSize = 40;
const double _rowGap = 12;
const double _rowTextInset = _rowPadding + _avatarSize + _rowGap;

/// The smallest an activity row may be drawn, whatever its text scale: the
/// row is a control once it can be edited, and 44 dp is the smallest target a
/// finger or a switch can be expected to hit. The avatar already makes a row
/// taller than this; the floor exists so a row never collapses below it.
const double _rowMinHeight = 44;
const double _rowEditSize = 18;

/// The one type scale this screen uses, top down: a caption that names a
/// figure, the figure itself, a card or section title, and a row's own title
/// and meta line. Reference proportions are kept - the hero amount is still
/// the display size and the tiles still sit one step below it - but every card
/// now draws from these numbers and nothing else. 18 dp w800 is the size
/// theme.md allows before an amount may be drawn in red or green, and it is the
/// size the All Transactions rows use, so both lists scan identically.
const double _labelSize = 12;
const double _metaSize = 12;
const double _rowTitleSize = 15;
const double _rowAmountSize = 18;
const double _cardTitleSize = 16;
const double _tileValueSize = 24;
const double _displaySize = 38;

/// The caption above a figure, used by the hero and both tiles. One spec
/// app-wide: the entry screens' `EntryFormLayout.caption` is the same 12 sp
/// at the same weight and tracking, so a label never changes voice between
/// Home and the form.
const TextStyle _cardLabel = TextStyle(
  fontSize: _labelSize,
  height: 1.25,
  letterSpacing: 0.4,
  fontWeight: FontWeight.w800,
);

/// The quiet meta line: a date, a category, an entry count.
const TextStyle _meta = TextStyle(
  fontSize: _metaSize,
  height: 1.3,
  color: AppColors.softText,
  fontWeight: FontWeight.w500,
);

/// Money text. Tabular figures keep the digits of every amount the same width,
/// so a column of figures lines up at the decimal instead of jittering with
/// the width of each glyph.
TextStyle _money({
  required double size,
  required Color color,
  double letterSpacing = 0,
  double height = 1.1,
  FontWeight weight = FontWeight.w800,
}) {
  return TextStyle(
    fontSize: size,
    height: height,
    letterSpacing: letterSpacing,
    fontWeight: weight,
    color: color,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
}

/// S1 - Home / My Khata. See docs/spec/screens.md#s1--home--my-khata.
///
/// A presentational seam: the parent supplies a live [summary] and the
/// [onAddEntry] / [onViewAll] / [onRecentEntry] callbacks. With no [summary]
/// the screen shows clearly labelled sample figures. It reads no storage,
/// holds no state and never edits an entry itself: a recent row only becomes a
/// control when its entry is stored *and* the parent supplied a handler.
///
/// The layout gives the active ledger and remaining balance first priority,
/// then keeps the income/expense split, recent activity and primary action
/// close together. Illustrations are local assets: the screen works offline.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    this.language = AppLanguage.en,
    this.summary,
    this.onAddEntry,
    this.onViewAll,
    this.khataName,
    this.onSwitchKhata,
    this.categoryStore,
    this.onSettings,
    this.onRecentEntry,
  });

  final AppLanguage language;
  final CategoryStore? categoryStore;
  final VoidCallback? onSettings;

  AppStrings get _strings => AppStrings(language);

  /// Live figures to render. `null` selects the seeded sample preview.
  final LedgerSummary? summary;

  /// CTA action; a null callback leaves the button visibly disabled.
  final VoidCallback? onAddEntry;

  /// *View All* action; a null callback leaves that affordance disabled.
  final VoidCallback? onViewAll;

  /// Edit action for one recent row. A row is only actionable when this
  /// callback is supplied *and* the entry it draws has a stored
  /// [LedgerEntry.id]: sample preview rows and anything without an id stay
  /// plain text, announce no edit affordance and never call back. The screen
  /// itself neither edits nor navigates - the parent opens the editor from the
  /// callback.
  final ValueChanged<LedgerEntry>? onRecentEntry;

  final String? khataName;
  final VoidCallback? onSwitchKhata;

  static const double _pagePadding = 16;
  static const double _cardGap = 12;

  /// The gap above a section header, one step wider than the gap between two
  /// cards, so a header reads as the start of a block and not as a third card.
  static const double _sectionGap = 20;

  @override
  Widget build(BuildContext context) {
    final bool preview = summary == null;
    final LedgerSummary visibleSummary =
        summary ??
        LedgerSummary(
          openingBalancePaise: kSeedOpeningBalancePaise,
          entries: kSeedEntries,
        );
    final List<LedgerEntry> recent = visibleSummary.recent();
    final LedgerSummaryTotals totals = visibleSummary.totals;

    return Scaffold(
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            _pagePadding,
            10,
            _pagePadding,
            10,
          ),
          decoration: BoxDecoration(
            color: AppColors.creamBackground,
            image: const DecorationImage(
              image: AssetImage('assets/illustrations/home_landscape.png'),
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
            ),
            border: Border(
              top: BorderSide(color: AppColors.outline.withValues(alpha: 0.55)),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.darkText.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Hero(
            tag: 'add-entry-fab',
            child: FilledButton.icon(
              key: const Key('home-add-entry'),
              onPressed: onAddEntry,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                minimumSize: const Size.fromHeight(56),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.add, size: 30),
              label: Text(
                _strings.text(AppString.addNewEntry),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
      body: TabHeaderInset(
        topGap: 12,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.fromLTRB(
                    _pagePadding,
                    12,
                    _pagePadding,
                    20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (khataName != null ||
                          onSwitchKhata != null) ...<Widget>[
                        _ActiveKhataCard(
                          strings: _strings,
                          name:
                              khataName ??
                              _strings.text(AppString.personalKhata),
                          onTap: onSwitchKhata,
                          onSettings: onSettings,
                        ),
                        const SizedBox(height: _cardGap),
                      ],
                      _BalanceCard(
                        strings: _strings,
                        remainingPaise: totals.remainingPaise,
                      ),
                      const SizedBox(height: _cardGap),
                      _summaryRow(totals),
                      const SizedBox(height: _sectionGap),
                      _SectionHeader(
                        strings: _strings,
                        title: _strings.text(AppString.recentTransactions),
                        onViewAll: onViewAll,
                      ),
                      // The header and the list it heads are one block: the sheet
                      // starts one card gap below the header, the same 12 dp that
                      // separates the cards above it.
                      const SizedBox(height: _cardGap),
                      if (recent.isEmpty)
                        _EmptyTransactions(_strings)
                      else
                        _RecentList(
                          strings: _strings,
                          entries: recent,
                          preview: preview,
                          onEntry: onRecentEntry,
                          categoryStore: categoryStore,
                        ),
                      if (preview) ...<Widget>[
                        const SizedBox(height: 10),
                        Center(
                          child: Text(
                            _strings.text(AppString.homePreview),
                            textAlign: TextAlign.center,
                            style: _meta.copyWith(letterSpacing: 0.2),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Income and expense are one comparison, so they share one frame with a
  /// 1 px rule between them instead of sitting in two boxes: the pair reads
  /// together and the two figures line up on the same baseline.
  Widget _summaryRow(LedgerSummaryTotals totals) {
    return Container(
      key: const Key('home-summary-row'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: AppColors.outline.withValues(alpha: _edge)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _SummaryTile(
                strings: _strings,
                label: _strings.text(AppString.totalIncome),
                paise: totals.totalIncomePaise,
                color: AppColors.incomeGreen,
                icon: Icons.south_rounded,
                direction: _strings.text(AppString.income).toLowerCase(),
              ),
            ),
            const _ColumnRule(),
            Expanded(
              child: _SummaryTile(
                strings: _strings,
                label: _strings.text(AppString.totalExpense),
                paise: totals.totalExpensePaise,
                color: AppColors.expenseRed,
                icon: Icons.north_east_rounded,
                direction: _strings.text(AppString.expense).toLowerCase(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An always-visible switcher row makes the active ledger easy to confirm.
class _ActiveKhataCard extends StatelessWidget {
  const _ActiveKhataCard({
    required this.strings,
    required this.name,
    required this.onTap,
    this.onSettings,
  });

  final AppStrings strings;
  final String name;
  final VoidCallback? onTap;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    return FullWidthTabHeader(
      inset: 16,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                key: const Key('switch-khata'),
                button: onTap != null,
                enabled: onTap != null,
                label:
                    '$name, ${strings.text(AppString.activeKhata)}${onTap == null ? '' : ', ${strings.text(AppString.tapToSwitch)}'}',
                onTap: onTap,
                excludeSemantics: true,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(_cardRadius),
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(_cardRadius),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: <Widget>[
                          ClipOval(
                            child: Image.asset(
                              'assets/illustrations/home_brand.png',
                              width: 62,
                              height: 62,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  strings
                                      .text(AppString.activeKhata)
                                      .toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _cardLabel.copyWith(
                                    color: AppColors.onPrimary,
                                  ),
                                ),
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: _cardTitleSize,
                                          height: 1.3,
                                          letterSpacing: -0.1,
                                          color: AppColors.onPrimary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: AppColors.onPrimary,
                                    ),
                                  ],
                                ),
                                const Text(
                                  'Plan • Track • Save',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    fontSize: _metaSize,
                                    height: 1.3,
                                    color: AppColors.onPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (onSettings != null) ...<Widget>[
              const SizedBox(width: 8),
              Material(
                color: AppColors.secondaryGreen,
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: onSettings,
                  // Localized, so a Bengali screen does not announce an English
                  // control: the tooltip is the button's only accessible name.
                  tooltip: strings.text(AppString.settings),
                  color: AppColors.onPrimary,
                  icon: const Icon(Icons.settings),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Green balance card with a bundled AI wallet illustration.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.strings, required this.remainingPaise});

  final AppStrings strings;
  final int remainingPaise;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('home-balance-card'),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[AppColors.primaryGreen, AppColors.headerGreen],
        ),
        borderRadius: BorderRadius.circular(_cardRadius),
        border: const Border(
          bottom: BorderSide(color: AppColors.golden, width: 3),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.darkText.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      // One row, one column of text: label, figure, and the vertical rhythm
      // between them - the same three steps the tiles below use.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Row(
          children: <Widget>[
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/illustrations/home_balance_wallet.png',
                  width: 68,
                  height: 78,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Container(
              width: _separator,
              height: 68,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: AppColors.golden,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    strings.text(AppString.remainingBalance),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _cardLabel.copyWith(color: AppColors.onPrimary),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      strings.money(remainingPaise),
                      maxLines: 1,
                      softWrap: false,
                      style: _money(
                        size: _displaySize,
                        color: AppColors.golden,
                        letterSpacing: -0.5,
                        height: 1.05,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            ExcludeSemantics(
              child: ClipOval(
                child: Image.asset(
                  'assets/illustrations/home_balance_book.png',
                  width: 85,
                  height: 85,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One half of the income/expense summary row.
class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.strings,
    required this.label,
    required this.paise,
    required this.color,
    required this.icon,
    required this.direction,
  });

  final AppStrings strings;
  final String label;
  final int paise;
  final Color color;
  final IconData icon;
  final String direction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label, $direction, ${strings.money(paise)}',
      child: ExcludeSemantics(
        // No frame of its own: the row it sits in supplies the surface, the
        // radius and the rule, so a half is a half and not a second card.
        child: Padding(
          padding: const EdgeInsets.all(_rowPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.13),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 16, color: color),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _cardLabel.copyWith(color: AppColors.softText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  strings.money(paise),
                  maxLines: 1,
                  softWrap: false,
                  style: _money(
                    size: _tileValueSize,
                    color: color,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 1 px rule that splits the summary pair, drawn like every other rule in
/// the app: the same beige, the same single pixel, no shadow.
class _ColumnRule extends StatelessWidget {
  const _ColumnRule();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: _separator,
      child: ColoredBox(color: AppColors.beige),
    );
  }
}

/// Empty ledger state, kept plain and actionable.
class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions(this.strings);

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        // Quieter than a card that carries data: the frame holds the space, it
        // does not compete with the figures above it.
        border: Border.all(
          color: AppColors.outline.withValues(alpha: _softEdge),
        ),
      ),
      child: Column(
        children: <Widget>[
          Image.asset(
            'assets/illustrations/home_brand.png',
            width: 72,
            height: 72,
          ),
          const SizedBox(height: 12),
          Text(
            strings.text(AppString.homeEmpty),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.darkText,
              fontSize: _cardTitleSize,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            // Language, not a display name: `AppLanguage.bn` never equals
            // `'Bengali'`, so comparing `.name` silently left every Bengali
            // screen showing the English instruction.
            strings.language == AppLanguage.bn
                ? "শুরু করতে নিচের বড় '+' বাটনে চাপুন - প্রথম আয় বা খরচ যোগ করুন।"
                : "Tap the big '+' button below to add your first expense or income.",
            key: const Key('home-empty-instruction'),
            textAlign: TextAlign.center,
            style: _meta.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// *Recent Transactions* with an accessible `View All` button.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.strings,
    required this.title,
    this.onViewAll,
  });

  final AppStrings strings;
  final String title;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onViewAll != null;
    final Color tint = enabled
        ? AppColors.primaryGreen
        : AppColors.navigationGrey;

    // The 4 dp accent bar plus 8 dp of air put the title on the same left
    // column as the text inside the hero card (16 page padding + 12 card
    // padding), and leave View All flush with the right card edge.
    return Row(
      children: <Widget>[
        Container(
          width: 4,
          height: _cardTitleSize,
          decoration: BoxDecoration(
            color: enabled
                ? AppColors.primaryGreen
                : AppColors.navigationGrey.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: _cardTitleSize,
              fontWeight: FontWeight.w700,
              color: AppColors.darkText,
              letterSpacing: -0.1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onViewAll,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(44, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: tint,
                backgroundColor: AppColors.lightGreen,
                shape: const StadiumBorder(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    strings.text(AppString.viewAll),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tint,
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 18, color: tint),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The recent rows on a single sheet.
///
/// One card, one border, and a quiet 1 px rule between rows instead of a box
/// around every row: the list reads as one object to scan, and the amounts
/// line up in a column because the right edge is the same for all of them.
class _RecentList extends StatelessWidget {
  const _RecentList({
    required this.strings,
    required this.entries,
    required this.preview,
    this.onEntry,
    this.categoryStore,
  });

  final AppStrings strings;
  final List<LedgerEntry> entries;
  final bool preview;
  final ValueChanged<LedgerEntry>? onEntry;
  final CategoryStore? categoryStore;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('recent-transactions-card'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: AppColors.outline.withValues(alpha: _edge)),
      ),
      // The sheet clips its own corners: an actionable row paints an ink
      // highlight, and the first and last rows must not square off the card.
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int index = 0; index < entries.length; index++) ...<Widget>[
            if (index > 0) const _RowRule(),
            _row(entries[index]),
          ],
        ],
      ),
    );
  }

  /// A row's category labels come from the store, so each row is built inside
  /// its own catalog scope, exactly as before.
  Widget _row(LedgerEntry entry) {
    // The callback is passed down unconditionally: the row decides whether it
    // is actionable, so the rule for "editable" lives in exactly one place.
    final Key rowKey = Key('home-recent-${entry.title}');
    if (categoryStore == null) {
      return _RecentTransactionRow(
        strings: strings,
        entry: entry,
        preview: preview,
        onTap: onEntry,
        rowKey: rowKey,
      );
    }
    return CategoryCatalog(
      store: categoryStore!,
      builder: (context, categories) => _RecentTransactionRow(
        strings: strings,
        entry: entry,
        preview: preview,
        onTap: onEntry,
        // A preview row is keyed by its title, so a test can reach one row
        // without reaching the others.
        rowKey: rowKey,
        categories: categories,
      ),
    );
  }
}

/// The 1 px rule between two rows, inset to the text column so it never cuts
/// under the avatars.
class _RowRule extends StatelessWidget {
  const _RowRule();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: _rowTextInset),
      child: SizedBox(
        height: _separator,
        child: ColoredBox(color: AppColors.beige),
      ),
    );
  }
}

/// One recent transaction: category cue, clear description and signed amount.
class _RecentTransactionRow extends StatelessWidget {
  const _RecentTransactionRow({
    required this.strings,
    required this.entry,
    required this.preview,
    this.onTap,
    this.rowKey,
    this.categories,
  });

  final AppStrings strings;
  final LedgerEntry entry;
  final bool preview;
  final ValueChanged<LedgerEntry>? onTap;
  final Key? rowKey;
  final List<CustomCategory>? categories;

  /// A row is actionable only when the parent asked for edits *and* the entry
  /// is stored: a preview or seed row has no id, so there is nothing an editor
  /// could legitimately write back. Same rule as the All Transactions rows.
  bool get _actionable => onTap != null && entry.id != null;

  @override
  Widget build(BuildContext context) {
    final bool isIncome = entry.type == EntryType.income;
    final Color amountColor = isIncome
        ? AppColors.incomeGreen
        : AppColors.expenseRed;

    // The stored category is translated for display only; the title is the
    // user's own text and is never touched.
    final String categoryName = categories == null
        ? _categoryLabel(strings, entry.category)
        : categoryDisplayName(strings.language, entry.category, categories!);
    final String title = preview
        ? _previewTitle(strings, entry.title)
        : (categories != null && entry.title == entry.category
              ? categoryName
              : entry.title);

    // The one place a row becomes a control: the parent's handler plus a
    // stored id. Everything else - preview rows, seed rows, a Home screen
    // built without `onRecentEntry` - stays inert text that announces no edit.
    final VoidCallback? tap = _actionable ? () => onTap!(entry) : null;

    // No box of its own: the list supplies the surface and the rule, the row
    // supplies only its three columns - cue, words, amount.
    return Semantics(
      key: rowKey,
      container: true,
      button: tap != null,
      // A stored row is an enabled control; an inert row is plain text, not a
      // greyed-out control - so the flag is absent rather than false.
      enabled: tap == null ? null : true,
      onTap: tap,
      // Title, direction, category, amount and date as one node. The amount is
      // drawn in green or red, which is exactly why the direction must also be
      // in words: colour alone never carries the meaning. `editable` appends
      // the localized "Tap to edit" only where a tap really edits.
      label: strings.transactionLabel(
        title: title,
        category: categoryName,
        amountPaise: entry.amountPaise,
        income: isIncome,
        at: entry.at,
        editable: tap != null,
      ),
      // The artwork is decorative and every word below is already in the label
      // above, so the announcer reads the row once, not twice.
      child: ExcludeSemantics(
        // A transparent Material so the ink has something to paint on without
        // adding a surface, a shadow or a second card inside the sheet.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: tap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _rowMinHeight),
              child: Padding(
                padding: const EdgeInsets.all(_rowPadding),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      width: _avatarSize,
                      height: _avatarSize,
                      decoration: BoxDecoration(
                        color: _categoryTint(entry.category),
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: CategoryArtwork(
                          category: entry.category,
                          size: _avatarSize,
                          fallbackColor: _categoryColor(entry.category),
                          customCategory: categories == null
                              ? null
                              : findCustomCategory(entry.category, categories!),
                        ),
                      ),
                    ),
                    const SizedBox(width: _rowGap),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: _rowTitleSize,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                              color: AppColors.darkText,
                            ),
                          ),
                          // The category is only repeated when it adds
                          // information, so a row never shows the same words
                          // twice. Both meta lines are the caption size, which
                          // is what makes the amount column the only place the
                          // eye has to stop.
                          if (categories != null &&
                              categoryName != title) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              categoryName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _meta,
                            ),
                          ],
                          const SizedBox(height: 1),
                          Text(
                            strings.dateTime(entry.at),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _meta,
                          ),
                        ],
                      ),
                    ),
                    // The visual half of the edit affordance, drawn only where
                    // a tap really edits - the words are in the row's label
                    // ("Tap to edit"), localized with the rest of the screen.
                    if (tap != null) ...<Widget>[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.edit_outlined,
                        size: _rowEditSize,
                        color: AppColors.softText,
                      ),
                    ],
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            isIncome
                                ? '+${strings.money(entry.amountPaise)}'
                                : strings.money(entry.amountPaise),
                            maxLines: 1,
                            softWrap: false,
                            textAlign: TextAlign.right,
                            style: _money(
                              size: _rowAmountSize,
                              color: amountColor,
                              letterSpacing: -0.2,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _categoryTint(String category) =>
      _categoryColor(category).withValues(alpha: 0.14);

  /// Category colours come from theme tokens only.
  Color _categoryColor(String category) {
    switch (category) {
      case 'Shopping':
        return AppColors.primaryGreen;
      case 'Food':
        return AppColors.orange;
      case 'Travel':
        return AppColors.secondaryGreen;
      case 'Bills':
        return AppColors.golden;
      case 'Gifts':
        return AppColors.expenseRed;
      default:
        return AppColors.navigationGrey;
    }
  }
}

String _categoryLabel(AppStrings strings, String category) {
  final AppString? key = switch (category) {
    'Shopping' => AppString.shopping,
    'Food' => AppString.food,
    'Travel' => AppString.travel,
    'Bills' => AppString.bills,
    'Gifts' => AppString.gifts,
    'Income' => AppString.income,
    'Expense' => AppString.expense,
    _ => null,
  };
  return key == null ? category : strings.text(key);
}

String _previewTitle(AppStrings strings, String title) {
  final AppString? key = switch (title) {
    'Grocery Shopping' => AppString.groceryShopping,
    'Lunch with Friends' => AppString.lunchWithFriends,
    'Mobile Recharge' => AppString.mobileRecharge,
    'Gift for Mom' => AppString.giftForMom,
    'Bus Fare' => AppString.busFare,
    'Tea with Team' => AppString.teaWithTeam,
    _ => null,
  };
  return key == null ? title : strings.text(key);
}
