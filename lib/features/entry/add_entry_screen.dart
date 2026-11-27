import 'dart:ui' as ui;

// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated
// dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/money.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ledger_header_background.dart'
    show HeaderCornerLeaves;
import 'category_picker.dart';
import 'category_store.dart';

enum EntryFormKind { expense, income }

class EntryFormResult {
  const EntryFormResult({
    required this.kind,
    required this.amountPaise,
    required this.category,
    required this.description,
    required this.occurredAt,
  });

  final EntryFormKind kind;
  final int amountPaise;
  final String category;
  final String description;
  final DateTime occurredAt;
}

/// One choice in the expense category row: the stored ID and display label.
class _CategoryOption {
  const _CategoryOption(this.id, this.label);

  final String id;
  final AppString label;
}

/// The form's typographic scale and spacing rhythm, shared by Add Entry and
/// the transaction editor so the two screens cannot drift apart.
///
/// Everything is on an 8 dp grid ([gap], [pagePadding]) with one card radius
/// family for input frames (18) and for the save area (20). Colours still come
/// from [AppColors] only; these are sizes and type, not a second token set.
class EntryFormLayout {
  const EntryFormLayout._();

  /// Page gutter and the single step between groups.
  static const double pagePadding = 16;
  static const double gap = 8;

  /// Radius of a framed input row.
  static const double frameRadius = 18;

  /// Radius of the save area card and the category tiles.
  static const double cardRadius = 20;

  /// Height of a framed row at normal text scale; a minimum, not a cap.
  static const double fieldMinHeight = 48;

  /// The same minimum on a short phone, where every group has to share one
  /// screen with the rest of the form.
  static const double compactFieldMinHeight = 40;

  /// The amount is the loudest element on the screen: 40 sp, tabular figures.
  static const TextStyle amount = TextStyle(
    fontSize: 40,
    height: 1.15,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    fontFeatures: <ui.FontFeature>[ui.FontFeature.tabularFigures()],
    color: AppColors.darkText,
  );

  /// The ₹ that sits on the amount's baseline, just before the first digit.
  static const TextStyle currency = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    color: AppColors.primaryGreen,
  );

  static const TextStyle value = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.darkText,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.4,
    color: AppColors.softText,
  );

  /// A calm single line under the amount: what the field expects, in words.
  static const TextStyle helper = TextStyle(
    fontSize: 12,
    height: 1.3,
    color: AppColors.softText,
  );

  static const TextStyle error = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: AppColors.expenseRed,
  );

  /// The small bold caption the design puts above every framed field
  /// (`Amount`, `Date`, `Category`, `Description`): a step quieter than the
  /// value it names.
  static Widget captionRow(
    String text,
    IconData icon, {
    double iconSize = 18,
  }) => _SectionLabel(text, icon, iconSize);
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, this.icon, [this.iconSize = 18]);

  final String text;
  final IconData icon;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: AppColors.primaryGreen, size: iconSize),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: EntryFormLayout.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Collects an entry without owning navigation or persistence.
///
/// S2 in docs/spec/screens.md, styled after the "Add Expense" phone in
/// docs/design/ui-preview.png: cream canvas, green header and action, a loud
/// tabular amount, segmented Expense/Income, framed date and description rows,
/// rounded category icon tiles, a live "After saving" preview and one save
/// action at the end of the form.
class AddEntryScreen extends StatefulWidget {
  const AddEntryScreen({
    super.key,
    this.language = AppLanguage.en,
    this.categoryStore,
    this.initialAmountPaise,
    this.initialKind,
    this.initialDescription,
    required this.openingBalancePaise,
    required this.onSave,
  });

  final AppLanguage language;

  final CategoryStore? categoryStore;
  final int? initialAmountPaise;
  final EntryFormKind? initialKind;
  final String? initialDescription;
  final int openingBalancePaise;
  final ValueChanged<EntryFormResult> onSave;

  @override
  State<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends State<AddEntryScreen> {
  AppStrings get _strings => AppStrings(widget.language);

  // Keep the whole form visible on ordinary-height phones. Large accessibility
  // text and the keyboard retain the naturally scrollable layout.
  bool get _compact => isCompactFormViewport(context);

  static const List<_CategoryOption> _categories = <_CategoryOption>[
    _CategoryOption('Shopping', AppString.shopping),
    _CategoryOption('Food', AppString.food),
    _CategoryOption('Travel', AppString.travel),
    _CategoryOption('Bills', AppString.bills),
    _CategoryOption('Gifts', AppString.gifts),
  ];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// Anchors that let a failed save scroll the first invalid input into
  /// view. They sit on the section columns, never on the fields themselves,
  /// whose own keys are how tests and semantics address them.
  final GlobalKey _amountSectionKey = GlobalKey();
  final GlobalKey _categorySectionKey = GlobalKey();
  final GlobalKey _descriptionSectionKey = GlobalKey();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _description = TextEditingController();

  /// Focus is owned here rather than left to the fields, because the frame
  /// that turns green is the *card around* the field, not the field itself.
  final FocusNode _amountFocus = FocusNode();
  final FocusNode _descriptionFocus = FocusNode();
  EntryFormKind _kind = EntryFormKind.expense;
  String? _category;
  bool _showCategoryError = false;
  bool _saving = false;

  /// True once a save was pressed on an incomplete form, so the inline
  /// amount error can appear even while the field is still empty. Both save
  /// actions stay live while the form is idle, so pressing either one is
  /// how the form names what it is missing.
  bool _attemptedSave = false;

  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final amount = widget.initialAmountPaise;
    if (amount != null && amount > 0) {
      _amount.text =
          '${amount ~/ 100}.${(amount % 100).toString().padLeft(2, '0')}';
    }
    _kind = widget.initialKind ?? EntryFormKind.expense;
    _description.text = widget.initialDescription ?? '';
    final DateTime now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    _amountFocus.addListener(_handleFocusChange);
    _descriptionFocus.addListener(_handleFocusChange);
  }

  /// Repaints the frame of whichever field gained or lost focus.
  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _amountFocus.dispose();
    _descriptionFocus.dispose();
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  /// The live "After saving" figure: the balance this entry would leave, or
  /// `null` while the amount is not a valid positive one.
  int? _projectedBalance() {
    final int? paise = parsePaise(_amount.text);
    if (paise == null) return null;
    return _kind == EntryFormKind.income
        ? widget.openingBalancePaise + paise
        : widget.openingBalancePaise - paise;
  }

  Future<void> _pickDate() async {
    if (_saving) return;
    final bool bengali = widget.language == AppLanguage.bn;
    final DateTime? chosen = await showDatePicker(
      context: context,
      helpText: bengali ? _DatePickerCopy.help.text(widget.language) : null,
      cancelText: bengali ? _strings.text(AppString.cancel) : null,
      confirmText: bengali
          ? _DatePickerCopy.confirm.text(widget.language)
          : null,
      fieldLabelText: bengali ? _strings.text(AppString.date) : null,
      errorFormatText: bengali
          ? _DatePickerCopy.invalidFormat.text(widget.language)
          : null,
      errorInvalidText: bengali
          ? _DatePickerCopy.outOfRange.text(widget.language)
          : null,
      barrierLabel: bengali ? _strings.text(AppString.cancel) : null,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(DateTime.now().year + 100, 12, 31),
    );
    if (chosen != null && mounted) {
      setState(() => _date = DateTime(chosen.year, chosen.month, chosen.day));
    }
  }

  void _save() {
    if (_saving) return;
    // Drop focus first: the frames lose their green ring and the inline
    // errors below them become the thing to read.
    _amountFocus.unfocus();
    _descriptionFocus.unfocus();
    final FormState? form = _formKey.currentState;
    final bool validFields = form?.validate() ?? false;
    final bool validAmount = parsePaise(_amount.text) != null;
    final bool validCategory =
        _kind == EntryFormKind.income || _category != null;
    setState(() {
      _showCategoryError = !validCategory;
      _attemptedSave = true;
    });
    if (!validFields || !validAmount || !validCategory) {
      _revealFirstInvalid(
        validAmount: validAmount,
        validCategory: validCategory,
      );
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    widget.onSave(
      EntryFormResult(
        kind: _kind,
        amountPaise: parsePaise(_amount.text)!,
        category: _kind == EntryFormKind.income ? 'Income' : _category!,
        description: _description.text,
        occurredAt: _date,
      ),
    );
    // The host normally pops this route once the write lands, which disposes
    // the state. When it does not (a directly pumped screen), the button must
    // not stay stuck in its saving look for the rest of the session.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _saving) setState(() => _saving = false);
    });
  }

  /// Brings the first invalid input, in on-screen order (amount, then
  /// category, then description), into view after the error rows have had
  /// a frame to appear, and focuses the field when it is one that takes
  /// text. A category is not focusable, so scrolling is all it gets.
  void _revealFirstInvalid({
    required bool validAmount,
    required bool validCategory,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _saving) return;
      if (!validAmount) {
        _scrollIntoView(_amountSectionKey);
        _amountFocus.requestFocus();
      } else if (!validCategory) {
        _scrollIntoView(_categorySectionKey);
      } else {
        _scrollIntoView(_descriptionSectionKey);
        _descriptionFocus.requestFocus();
      }
    });
  }

  void _scrollIntoView(GlobalKey key) {
    final BuildContext? target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      alignment: 0.15,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _selectKind(EntryFormKind kind) {
    if (_saving) return;
    HapticFeedback.lightImpact();
    setState(() {
      _kind = kind;
      _showCategoryError = false;
    });
  }

  void _selectCategory(String category) {
    if (_saving) return;
    HapticFeedback.lightImpact();
    setState(() {
      _category = category;
      _showCategoryError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final bool future = _date.isAfter(DateTime(now.year, now.month, now.day));

    return Hero(
      tag: 'add-entry-fab',
      child: Scaffold(
        backgroundColor: AppColors.creamBackground,
        appBar: _appBar(),
        // Fill the usable viewport when the form is short, but keep natural
        // scrolling when text, validation errors or the keyboard need more room.
        body: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints viewport) {
              final double verticalPadding = _compact ? 6 : EntryFormLayout.gap;
              return Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: EntryFormLayout.pagePadding,
                    vertical: verticalPadding,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (viewport.maxHeight - verticalPadding * 2)
                          .clamp(0.0, double.infinity),
                    ),
                    child: Column(
                      // Extra room belongs between the form sections, not in
                      // a dead area below Save. Minimum gaps remain on small
                      // screens; no fixed height, Spacer or intrinsic pass.
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _amountSection(),
                        _sectionGap(),
                        _kindSelector(),
                        _sectionGap(),
                        _dateSection(future: future),
                        _sectionGap(),
                        _categorySection(),
                        _sectionGap(),
                        _descriptionSection(),
                        _sectionGap(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _saveArea(),
                            SizedBox(height: _compact ? 4 : 12),
                            ExcludeSemantics(
                              child: Image(
                                key: const Key('entry-footer-artwork'),
                                image: const AssetImage(
                                  'assets/illustrations/entry_footer_leaves.png',
                                ),
                                height: _compact ? 16 : 44,
                                fit: BoxFit.fitWidth,
                                excludeFromSemantics: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// One grid step between groups on a short phone and two on a tall one.
  /// Compact stays deliberately tight: the whole form (amount, kind, date,
  /// category, description, save) has to fit above the fold at 360x640.
  double get _groupGap => _compact ? 6 : 16;

  Widget _sectionGap() => SizedBox(height: _groupGap);

  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      // White status-bar glyphs, matching the rest of the app's headers.
      systemOverlayStyle: SystemUiOverlayStyle.light,
      toolbarHeight: _compact ? 56 : 64,
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(_compact ? 6 : 10),
        child: SizedBox(height: _compact ? 6 : 10),
      ),
      flexibleSpace: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const CustomPaint(painter: _EntryHeaderPainter()),
          const Positioned(
            right: 0,
            bottom: 0,
            child: IgnorePointer(child: HeaderCornerLeaves()),
          ),
        ],
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: _strings.text(AppString.back),
        onPressed: () => Navigator.of(context).maybePop(),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: AppColors.onPrimary,
        ),
      ),
      titleSpacing: 0,
      title: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(EntryFormLayout.gap),
            child: Image.asset(
              'assets/illustrations/entry_header_notebook.png',
              width: _compact ? 34 : 40,
              height: _compact ? 34 : 40,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _strings.text(AppString.addEntry),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                  ),
                ),
                if (!_compact)
                  Text(
                    widget.language == AppLanguage.bn
                        ? 'হিসাব রাখুন নিয়মিত'
                        : 'Keep Your Account Updated',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: <Widget>[
        IconButton(
          // The header action and the main Save Entry button run the same
          // validation: both stay live while the form is idle, so pressing
          // either one on an empty form names everything it is missing.
          onPressed: _saving ? null : _save,
          tooltip: _strings.text(AppString.save),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: AppColors.onPrimary,
            disabledBackgroundColor: AppColors.navigationGrey.withValues(
              alpha: 0.35,
            ),
            disabledForegroundColor: AppColors.onPrimary,
          ),
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.onPrimary,
                  ),
                )
              : const Icon(Icons.save),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  /// Amount first and loudest: ₹ aligned to the first digit, tabular figures,
  /// a calm helper line instead of a floating label, errors under the frame.
  Widget _amountSection() {
    final bool focused = _amountFocus.hasFocus;
    final bool valid = parsePaise(_amount.text) != null;
    // An invalid amount flags itself once the field lets focus go, or as
    // soon as a save press has asked the form what it is missing. After a
    // save press the flag stays up even though the field is refocused, so
    // the user can read it while fixing the amount.
    final bool showError =
        !valid && (_attemptedSave || (!focused && _amount.text.isNotEmpty));
    return Column(
      key: _amountSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        EntryFormLayout.captionRow(
          _strings.text(AppString.amount),
          Icons.account_balance_wallet,
          iconSize: _compact ? 16 : 18,
        ),
        const SizedBox(height: EntryFormLayout.gap),
        // The frame is the card around the row, never an ancestor of the
        // amount field: the tests read the focused frame as the closest card
        // above the field, and a field inside its own frame would be its own.
        AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(
            _compact ? 12 : 16,
            _compact ? 6 : 12,
            _compact ? 10 : 12,
            _compact ? 6 : 12,
          ),
          decoration: BoxDecoration(
            color: focused ? AppColors.lightGreen : AppColors.warmIvory,
            borderRadius: BorderRadius.circular(EntryFormLayout.cardRadius),
            border: Border.all(
              color: showError
                  ? AppColors.expenseRed
                  : focused
                  ? AppColors.primaryGreen
                  : AppColors.beige.withValues(alpha: 0.9),
              width: focused || showError ? 1.6 : 1.2,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.headerGreen.withValues(
                  alpha: focused ? 0.12 : 0.06,
                ),
                blurRadius: focused ? 16 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // The caption above names the field; the frame's own semantics
              // label is merged in here so a screen reader reads it once.
              Semantics(
                label: _strings.text(AppString.amount),
                child: TextField(
                  key: const Key('amount-field'),
                  controller: _amount,
                  focusNode: _amountFocus,
                  enabled: !_saving,
                  maxLines: 1,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  style: EntryFormLayout.amount,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    // The error text lives under the frame (below), aligned
                    // with the card's own edge; the field's slot collapses.
                    errorStyle: const TextStyle(
                      fontSize: 0,
                      height: 0,
                      color: Colors.transparent,
                    ),
                    errorMaxLines: 1,
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Text('₹', style: EntryFormLayout.currency),
                    ),
                    // No `0.00` placeholder: an empty field shows only the
                    // ₹ the prefix carries, so a dead zero can never read
                    // as an amount the user already typed.
                  ),
                  // Validated by the screen, not by a form validator: the
                  // message belongs in the visible row under the frame, and
                  // a duplicate in the field's own slot would paint twice.
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _strings.text(AppString.amountPrecision),
                      maxLines: 2,
                      style: EntryFormLayout.helper,
                    ),
                  ),
                  const SizedBox(width: EntryFormLayout.gap),
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 20,
                    color: focused
                        ? AppColors.primaryGreen
                        : AppColors.softText,
                  ),
                ],
              ),
              if (showError) _inlineError(_strings.text(AppString.validAmount)),
            ],
          ),
        ),
      ],
    );
  }

  /// Expense | Income as the two-segment pill, directly under the amount.
  Widget _kindSelector() {
    return Material(
      color: AppColors.lightGreen,
      borderRadius: BorderRadius.circular(EntryFormLayout.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(_compact ? 3 : 4),
        child: Row(
          children: <Widget>[
            Expanded(child: _kindSegment(EntryFormKind.expense)),
            const SizedBox(width: 4),
            Expanded(child: _kindSegment(EntryFormKind.income)),
          ],
        ),
      ),
    );
  }

  Widget _kindSegment(EntryFormKind kind) {
    final bool selected = _kind == kind;
    final bool income = kind == EntryFormKind.income;
    final Color background = selected
        ? AppColors.primaryGreen
        : AppColors.warmIvory;
    // Unselected keeps the label in body ink and lets the arrow carry the
    // income/expense colour; selected inverts the pair. That is the same
    // treatment the editor uses, so the two forms read as one screen family.
    final Color textColor = selected ? AppColors.onPrimary : AppColors.darkText;
    final Color iconColor = selected
        ? AppColors.onPrimary
        : (income ? AppColors.incomeGreen : AppColors.expenseRed);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: _strings.text(income ? AppString.income : AppString.expense),
      excludeSemantics: true,
      onTap: () => _selectKind(kind),
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(EntryFormLayout.cardRadius - 4),
          ),
          side: BorderSide(
            color: selected ? AppColors.primaryGreen : AppColors.beige,
            width: 1.2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _selectKind(kind),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: _compact
                  ? EntryFormLayout.fieldMinHeight - 12
                  : EntryFormLayout.fieldMinHeight - 8,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 8,
                vertical: _compact ? 8 : 11,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    income ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 16,
                    color: iconColor,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _strings.text(
                        income ? AppString.income : AppString.expense,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The ivory input card used for the date and description rows: warm ivory
  /// fill, beige frame, one radius.
  ///
  /// The card holding focus turns green and lifts very slightly, so the row
  /// being edited is obvious without moving any of the other rows.
  Widget _framed({required Widget child, bool focused = false, Key? key}) {
    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      constraints: BoxConstraints(
        minHeight: _compact
            ? EntryFormLayout.compactFieldMinHeight
            : EntryFormLayout.fieldMinHeight,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: _compact ? 12 : 16,
        vertical: _compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: focused ? AppColors.lightGreen : AppColors.warmIvory,
        borderRadius: BorderRadius.circular(EntryFormLayout.frameRadius),
        border: Border.all(
          color: focused
              ? AppColors.primaryGreen
              : AppColors.accentGreen.withValues(alpha: 0.45),
          width: focused ? 1.6 : 1.2,
        ),
        boxShadow: focused
            ? <BoxShadow>[
                BoxShadow(
                  color: AppColors.primaryGreen.withValues(alpha: 0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }

  Widget _dateSection({required bool future}) {
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    final String mediumDate = localizations.formatMediumDate(_date);
    final String englishDate = mediumDate.contains('${_date.year}')
        ? mediumDate
        : '$mediumDate, ${_date.year}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        EntryFormLayout.captionRow(_strings.text(AppString.date), Icons.event),
        const SizedBox(height: EntryFormLayout.gap),
        ConstrainedBox(
          // 44 dp is the smallest comfortable tap target; the frame may shrink
          // on a short phone but the row the finger lands on never does.
          constraints: const BoxConstraints(minHeight: 44),
          child: InkWell(
            borderRadius: BorderRadius.circular(EntryFormLayout.frameRadius),
            onTap: _pickDate,
            child: _framed(
              key: const Key('date-field'),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.calendar_today,
                    size: 18,
                    color: AppColors.primaryGreen,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.language == AppLanguage.bn
                          ? _strings.day(_date)
                          : englishDate,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EntryFormLayout.value,
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: AppColors.softText,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (future) _inlineNote(_strings.text(AppString.futureDate)),
      ],
    );
  }

  Widget _categorySection() {
    return Column(
      key: _categorySectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        EntryFormLayout.captionRow(
          _strings.text(AppString.category),
          Icons.sell,
        ),
        const SizedBox(height: EntryFormLayout.gap),
        if (_kind == EntryFormKind.expense) ...<Widget>[
          _categoryChips(),
          if (_showCategoryError)
            _inlineError(_strings.text(AppString.pickCategory)),
        ] else
          _incomeCategoryPill(),
      ],
    );
  }

  /// The expense categories as the shared wrapping grid: even columns from
  /// [categoryGridColumns], so the whole set keeps one row on a narrow phone
  /// and custom choices plus the `More` cell flow underneath in the same
  /// rhythm. Nothing here scrolls sideways.
  Widget _categoryChips() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double gap = categoryGridGap(_compact);
        final double tileWidth = categoryGridTileWidth(
          constraints.maxWidth,
          _compact,
        );
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final _CategoryOption option in _categories)
              SizedBox(
                width: tileWidth,
                child: CategoryCell(
                  artworkKey: Key('category-artwork-${option.id}'),
                  checkKey: Key('category-check-${option.id}'),
                  label: _strings.text(option.label),
                  selected: _category == option.id,
                  onTap: () => _selectCategory(option.id),
                  icon: categoryGlyph(option.id),
                  width: tileWidth,
                  compact: _compact,
                ),
              ),
            if (widget.categoryStore != null)
              CustomCategoryChoices(
                store: widget.categoryStore!,
                language: widget.language,
                selected: _category,
                onSelected: _selectCategory,
              ),
          ],
        );
      },
    );
  }

  Widget _incomeCategoryPill() {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.lightGreen,
          borderRadius: BorderRadius.circular(EntryFormLayout.cardRadius),
          border: Border.all(color: AppColors.accentGreen),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.south_west_rounded,
              size: 16,
              color: AppColors.incomeGreen,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _strings.text(AppString.categoryIncome),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryGreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _descriptionSection() {
    return Column(
      key: _descriptionSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        EntryFormLayout.captionRow(
          _strings.text(AppString.description),
          Icons.edit_note,
        ),
        const SizedBox(height: EntryFormLayout.gap),
        _framed(
          focused: _descriptionFocus.hasFocus,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.edit, size: 18, color: AppColors.softText),
              ),
              const SizedBox(width: 12),
              Expanded(
                // The caption above the frame is a separate Text, so the field
                // carries its own accessible name.
                child: Semantics(
                  label: _strings.text(AppString.description),
                  child: TextFormField(
                    key: const Key('description-field'),
                    controller: _description,
                    focusNode: _descriptionFocus,
                    enabled: !_saving,
                    // One line on a short phone: two only cost height here,
                    // and the field still grows while it has focus.
                    maxLines: _compact ? 1 : 2,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.darkText,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      hintText: _strings.text(AppString.descriptionHint),
                      hintStyle: const TextStyle(
                        fontSize: 15,
                        color: AppColors.navigationGrey,
                      ),
                      helperText: _compact
                          ? null
                          : _strings.text(AppString.descriptionLimit),
                      helperStyle: EntryFormLayout.helper,
                      errorMaxLines: 4,
                      errorStyle: EntryFormLayout.error,
                    ),
                    validator: (String? value) =>
                        (value ?? '').characters.length > 120
                        ? _strings.text(AppString.descriptionTooLong)
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The live one-line projection: chosen kind, the typed amount and the
  /// khata's remaining balance after saving, e.g.
  /// `Expense ₹500 → remaining ₹5,920`. The balance is the screen's own
  /// ledger figure plus or minus the delta - no query, no other arithmetic.
  String _previewLine() {
    final int? paise = parsePaise(_amount.text);
    if (paise == null) return _strings.afterSave(null);
    final String kind = _strings.text(
      _kind == EntryFormKind.income ? AppString.income : AppString.expense,
    );
    final String remaining = _strings.text(AppString.remaining).toLowerCase();
    return '$kind ${_strings.money(paise)} → '
        '$remaining ${_strings.money(_projectedBalance()!)}';
  }

  /// The live projection and the one save action, composed as one column.
  ///
  /// The preview row always exists, so nothing above the button changes
  /// height when the amount becomes valid; the state is carried by the row's
  /// ink and icon instead.
  Widget _saveArea() {
    final bool hasAmount = parsePaise(_amount.text) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              _kind == EntryFormKind.income
                  ? Icons.trending_up
                  : Icons.trending_down,
              size: 18,
              color: AppColors.softText,
            ),
            const SizedBox(width: EntryFormLayout.gap),
            Expanded(
              child: Text(
                _previewLine(),
                key: const Key('after-saving-preview'),
                maxLines: 2,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: hasAmount ? FontWeight.w700 : FontWeight.w600,
                  color: hasAmount ? AppColors.headerGreen : AppColors.softText,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: _compact ? 8 : 12),
        FilledButton(
          key: const Key('save-entry-button'),
          // Live whenever the form is idle, even with no amount yet:
          // pressing it is how an incomplete form explains itself inline
          // instead of silently refusing. Only the in-flight saving state
          // disables it, so a write can never be submitted twice.
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(EntryFormLayout.frameRadius),
            ),
            minimumSize: const Size.fromHeight(EntryFormLayout.fieldMinHeight),
            disabledBackgroundColor: AppColors.beige,
            disabledForegroundColor: AppColors.softText,
          ),
          child: _saving
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: AppColors.softText,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _strings.text(AppString.save),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(Icons.save_outlined, size: 20),
                    const SizedBox(width: EntryFormLayout.gap),
                    Flexible(
                      child: Text(
                        _strings.text(AppString.saveEntry),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Small red note under its own field: the missing-category error and the
  /// amount flag, aligned to the field above rather than to the page edge.
  Widget _inlineError(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: EntryFormLayout.gap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline,
            size: 16,
            color: AppColors.expenseRed,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(message, style: EntryFormLayout.error)),
        ],
      ),
    );
  }

  /// The softer, non-blocking note (a future date can still be saved).
  Widget _inlineNote(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: EntryFormLayout.gap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline, size: 16, color: AppColors.orange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: EntryFormLayout.helper.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.darkText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Decorative curved header; all controls remain live AppBar widgets.
class _EntryHeaderPainter extends CustomPainter {
  const _EntryHeaderPainter();

  Path _wave(Size size, double bottom) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height - bottom + 8)
    ..cubicTo(
      size.width * .78,
      size.height - bottom - 24,
      size.width * .35,
      size.height - bottom + 20,
      0,
      size.height - bottom - 10,
    )
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(_wave(size, 0), Paint()..color = AppColors.golden);
    canvas.drawPath(
      _wave(size, 4),
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[AppColors.primaryGreen, AppColors.headerGreen],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

enum _DatePickerCopy {
  help('Select date', 'তারিখ বেছে নিন'),
  confirm('OK', 'ঠিক আছে'),
  invalidFormat('Invalid format.', 'তারিখের বিন্যাস সঠিক নয়।'),
  outOfRange('Out of range.', 'তারিখটি অনুমোদিত সীমার বাইরে।');

  const _DatePickerCopy(this.en, this.bn);

  final String en;
  final String bn;

  String text(AppLanguage language) => language == AppLanguage.bn ? bn : en;
}
