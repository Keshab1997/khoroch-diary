// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ledger_header_background.dart';
import 'add_entry_screen.dart';
import 'category_picker.dart';
import 'category_store.dart';

/// What the caller should do once the editor has closed.
enum TransactionEditResult { updated, deleted }

/// Edits (or deletes) one existing entry without owning navigation, storage or
/// undo. S2/S7 follow-on in docs/spec/screens.md.
///
/// The caller supplies the original [initial] values and two callbacks:
/// [onUpdate] receives the edited entry, [onDelete] takes no arguments (the
/// caller already knows which entry it is). Both return `true` only when the
/// change really landed. This screen never touches a ledger, so it cannot fake
/// a save:
///   * `true` pops with [TransactionEditResult.updated] or `.deleted`;
///   * `false` or a thrown error shows an inline message, re-enables the
///     actions and leaves the form exactly as it was;
///   * a cancelled delete confirmation calls nothing at all.
///
/// Money stays integer paise: the amount is parsed from the field into paise
/// and nothing here uses `double`. The untouched date keeps the original
/// [EntryFormResult.occurredAt] *exactly*, time and all; a date the user picks
/// is stored as that local calendar day at midnight, matching Add Entry.
class TransactionEditorScreen extends StatefulWidget {
  const TransactionEditorScreen({
    super.key,
    this.language = AppLanguage.en,
    this.categoryStore,
    required this.initial,
    required this.onUpdate,
    required this.onDelete,
  });

  final AppLanguage language;
  final CategoryStore? categoryStore;

  /// The entry being edited, shown prefilled and never mutated.
  final EntryFormResult initial;

  /// Persists the edited entry; `true` means it landed.
  final Future<bool> Function(EntryFormResult) onUpdate;

  /// Removes the entry; `true` means it landed.
  final Future<bool> Function() onDelete;

  @override
  State<TransactionEditorScreen> createState() =>
      _TransactionEditorScreenState();
}

class _TransactionEditorScreenState extends State<TransactionEditorScreen> {
  AppStrings get _strings => AppStrings(widget.language);

  /// Add Entry's own category set, in the same order, so the two screens agree.
  static const List<String> _standardCategories = <String>[
    'Shopping',
    'Food',
    'Travel',
    'Bills',
    'Gifts',
  ];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _description;

  /// The frame around a field - not the field itself - carries the focus
  /// ring, so the node lives here, matching Add Entry.
  final FocusNode _amountFocus = FocusNode();
  final FocusNode _descriptionFocus = FocusNode();

  late EntryFormKind _kind;
  late String _category;
  late DateTime _date;
  bool _showCategoryError = false;

  /// Non-null while a callback is in flight; also names which action is
  /// running, so both buttons can be disabled and the user can see why.
  AppString? _pendingLabel;

  /// Last honest failure message; cleared on the next attempt.
  AppString? _error;

  /// True while the discard confirmation is on screen, so a second back
  /// press cannot stack another copy of it.
  bool _discardPromptOpen = false;

  bool get _busy => _pendingLabel != null;

  /// Whether any field now differs from the entry the editor opened with.
  /// The amount compares as parsed paise, so retyping the same value in a
  /// different shape (`1234.5` for `1234.50`) is not a change; an amount
  /// that no longer parses counts as changed unless the text is exactly
  /// the original's. The date compares by local calendar day only, which
  /// is what keeps an untouched date's original timestamp intact.
  bool get _isDirty {
    final EntryFormResult initial = widget.initial;
    if (_kind != initial.kind || _category != initial.category) {
      return true;
    }
    if (_description.text != initial.description || !_dateUnchanged) {
      return true;
    }
    final int? amountPaise = parsePaise(_amount.text);
    if (amountPaise == null) {
      return _amount.text != _amountText(initial.amountPaise);
    }
    return amountPaise != initial.amountPaise;
  }

  /// The same short-phone rule Add Entry uses, so the shared category grid
  /// answers columns and gutters identically on both forms.
  bool get _compact => isCompactFormViewport(context);

  @override
  void initState() {
    super.initState();
    final EntryFormResult initial = widget.initial;
    _kind = initial.kind;
    _category = initial.category;
    _amount = TextEditingController(text: _amountText(initial.amountPaise));
    _description = TextEditingController(text: initial.description);
    _date = DateTime(
      initial.occurredAt.year,
      initial.occurredAt.month,
      initial.occurredAt.day,
    );
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

  /// Exact paise as an editable decimal string: 120000 becomes `1200.00`.
  String _amountText(int paise) {
    final int rupees = paise ~/ 100;
    final int fraction = paise % 100;
    return '$rupees.${fraction.toString().padLeft(2, '0')}';
  }

  bool get _dateUnchanged {
    final DateTime original = widget.initial.occurredAt;
    return _date.year == original.year &&
        _date.month == original.month &&
        _date.day == original.day;
  }

  /// The original category is always offered, even when it is not one of Add
  /// Entry's five, so editing can never silently drop it.
  List<String> get _categoryChoices {
    final List<String> choices = <String>[];
    final String original = widget.initial.category;
    if (original.trim().isNotEmpty && !_standardCategories.contains(original)) {
      choices.add(original);
    }
    choices.addAll(_standardCategories);
    return choices;
  }

  Future<void> _pickDate() async {
    if (_busy) {
      return;
    }
    final DateTime now = DateTime.now();
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
      lastDate: DateTime(now.year + 100, 12, 31),
    );
    if (chosen == null || !mounted) {
      return;
    }
    setState(() => _date = DateTime(chosen.year, chosen.month, chosen.day));
  }

  /// Runs a caller-owned callback and never lets its failure escape.
  Future<bool> _attempt(Future<bool> Function() action) async {
    try {
      return await action();
    } catch (_) {
      return false;
    }
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final FormState? form = _formKey.currentState;
    final bool fieldsValid = form?.validate() ?? false;
    final bool categoryValid = _category.trim().isNotEmpty;
    setState(() => _showCategoryError = !categoryValid);
    if (!fieldsValid || !categoryValid) {
      return;
    }
    final int? amountPaise = parsePaise(_amount.text);
    if (amountPaise == null) {
      return;
    }

    final EntryFormResult edited = EntryFormResult(
      kind: _kind,
      amountPaise: amountPaise,
      category: _category,
      description: _description.text,
      occurredAt: _dateUnchanged ? widget.initial.occurredAt : _date,
    );

    setState(() {
      _error = null;
      _pendingLabel = AppString.updating;
    });
    final bool updated = await _attempt(() => widget.onUpdate(edited));
    if (!mounted) {
      return;
    }
    if (updated) {
      setState(() => _pendingLabel = null);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      Navigator.of(context).pop(TransactionEditResult.updated);
      return;
    }
    setState(() {
      _pendingLabel = null;
      _error = AppString.editSaveFailed;
    });
  }

  Future<void> _delete() async {
    if (_busy) {
      return;
    }
    final bool confirmed = await _confirmDelete();
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _error = null;
      _pendingLabel = AppString.deleting;
    });
    final bool deleted = await _attempt(widget.onDelete);
    if (!mounted) {
      return;
    }
    if (deleted) {
      setState(() => _pendingLabel = null);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      Navigator.of(context).pop(TransactionEditResult.deleted);
      return;
    }
    setState(() {
      _pendingLabel = null;
      _error = AppString.deleteFailed;
    });
  }

  /// Explicit confirmation; anything but "Delete" must not reach the caller.
  Future<bool> _confirmDelete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final TextTheme text = Theme.of(dialogContext).textTheme;
        return AlertDialog(
          key: const Key('delete-confirm-dialog'),
          // Trimmed typography, not different copy: the question and the
          // consequence keep their exact strings, but fit a 360x640 dialog
          // without scrolling past the two actions.
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          title: Text(
            _strings.text(AppString.deleteQuestion),
            style: text.titleLarge?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          content: Text(
            _strings.text(AppString.deleteExplanation),
            style: text.bodyMedium,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          actions: <Widget>[
            TextButton(
              key: const Key('cancel-delete-button'),
              style: TextButton.styleFrom(
                minimumSize: const Size(64, 48),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_strings.text(AppString.cancel)),
            ),
            FilledButton(
              key: const Key('confirm-delete-button'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.warmIvory,
                foregroundColor: AppColors.expenseRed,
                minimumSize: const Size(88, 48),
                side: const BorderSide(color: AppColors.expenseRed),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                _strings.text(AppString.delete),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  /// The header back control: leave at once when nothing changed, ask
  /// first when leaving would throw edits away, and never move while a
  /// write is in flight.
  Future<void> _handleBack() async {
    if (_busy) {
      return;
    }
    if (!_isDirty) {
      Navigator.of(context).maybePop();
      return;
    }
    await _confirmDiscard();
  }

  /// System back lands here through [PopScope] whenever the route cannot
  /// pop freely. Keeping the draft (or dismissing the dialog) changes
  /// nothing and calls nothing; only an explicit Discard leaves, and it
  /// leaves without writing.
  Future<void> _confirmDiscard() async {
    if (_busy || _discardPromptOpen || !_isDirty) {
      return;
    }
    _discardPromptOpen = true;
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          key: const Key('discard-confirm-dialog'),
          scrollable: true,
          title: Text(_DiscardCopy.title.text(widget.language)),
          content: Text(_DiscardCopy.message.text(widget.language)),
          actions: <Widget>[
            TextButton(
              key: const Key('keep-editing-button'),
              style: TextButton.styleFrom(
                minimumSize: const Size(64, 48),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_DiscardCopy.keepEditing.text(widget.language)),
            ),
            FilledButton(
              key: const Key('discard-changes-button'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.warmIvory,
                foregroundColor: AppColors.expenseRed,
                minimumSize: const Size(88, 48),
                side: const BorderSide(color: AppColors.expenseRed),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                _DiscardCopy.discard.text(widget.language),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
    _discardPromptOpen = false;
    if (discard == true && mounted && !_busy) {
      Navigator.of(context).pop();
    }
  }

  void _selectKind(EntryFormKind kind) {
    if (_busy) {
      return;
    }
    setState(() => _kind = kind);
  }

  void _selectCategory(String category) {
    if (_busy) {
      return;
    }
    setState(() {
      _category = category;
      _showCategoryError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final bool future = _date.isAfter(DateTime(now.year, now.month, now.day));

    return PopScope(
      // Free to leave only when idle and untouched. A busy write blocks
      // back outright; unsaved edits route both the system back gesture
      // and the AppBar's default back button through the confirmation.
      canPop: !_busy && !_isDirty,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop || _busy) {
          return;
        }
        _confirmDiscard();
      },
      child: Scaffold(
        key: const Key('transaction-editor-screen'),
        backgroundColor: AppColors.creamBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.onPrimary,
          flexibleSpace: const LedgerHeaderBackground(child: SizedBox.expand()),
          leading:
              widget.language == AppLanguage.bn &&
                  (ModalRoute.of(context)?.impliesAppBarDismissal ?? false)
              ? IconButton(
                  icon: const BackButtonIcon(),
                  tooltip: _strings.text(AppString.back),
                  onPressed: _handleBack,
                )
              : null,
          title: Text(
            _strings.text(AppString.editTransaction),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                EntryFormLayout.pagePadding,
                EntryFormLayout.gap * 2,
                EntryFormLayout.pagePadding,
                EntryFormLayout.gap * 3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _amountField(),
                  const SizedBox(height: EntryFormLayout.gap),
                  _kindSelector(),
                  const SizedBox(height: EntryFormLayout.gap * 2),
                  EntryFormLayout.captionRow(
                    _strings.text(AppString.date),
                    Icons.event,
                  ),
                  const SizedBox(height: EntryFormLayout.gap),
                  _dateField(),
                  if (future) _inlineNote(_strings.text(AppString.futureDate)),
                  const SizedBox(height: EntryFormLayout.gap * 2),
                  EntryFormLayout.captionRow(
                    _strings.text(AppString.category),
                    Icons.sell,
                  ),
                  const SizedBox(height: EntryFormLayout.gap),
                  _categoryChips(),
                  if (_showCategoryError)
                    _inlineWarning(_strings.text(AppString.pickCategory)),
                  const SizedBox(height: EntryFormLayout.gap * 2),
                  EntryFormLayout.captionRow(
                    _strings.text(AppString.description),
                    Icons.edit_note,
                  ),
                  const SizedBox(height: EntryFormLayout.gap),
                  _descriptionField(),
                  const SizedBox(height: EntryFormLayout.gap * 2),
                  if (_pendingLabel != null)
                    _pendingCard(_strings.text(_pendingLabel!)),
                  if (_error != null) _errorCard(_strings.text(_error!)),
                  _previewRow(),
                  const SizedBox(height: EntryFormLayout.gap * 2),
                  _saveArea(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Expense | Income as the two-segment pill used by Add Entry.
  Widget _kindSelector() {
    return Material(
      color: AppColors.lightGreen,
      borderRadius: BorderRadius.circular(EntryFormLayout.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _kindSegment(
                EntryFormKind.expense,
                const Key('editor-kind-expense'),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _kindSegment(
                EntryFormKind.income,
                const Key('editor-kind-income'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindSegment(EntryFormKind kind, Key key) {
    final bool selected = _kind == kind;
    final bool income = kind == EntryFormKind.income;
    final String name = _strings.text(
      income ? AppString.income : AppString.expense,
    );
    final Color textColor = selected ? AppColors.onPrimary : AppColors.darkText;
    final Color iconColor = selected
        ? AppColors.onPrimary
        : (income ? AppColors.incomeGreen : AppColors.expenseRed);
    return Semantics(
      key: key,
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: name,
      excludeSemantics: true,
      onTap: () => _selectKind(kind),
      child: Material(
        color: selected ? AppColors.primaryGreen : AppColors.warmIvory,
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
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
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
                      name,
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

  /// Warm-ivory framed input row, matching Add Entry's fields - same radius,
  /// same minimum height, including the green frame that follows focus.
  Widget _framed({required Widget child, bool focused = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      constraints: const BoxConstraints(
        minHeight: EntryFormLayout.fieldMinHeight,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

  Widget _amountField() {
    return _framed(
      focused: _amountFocus.hasFocus,
      child: Semantics(
        label: _strings.text(AppString.amount),
        child: TextFormField(
          key: const Key('editor-amount-field'),
          controller: _amount,
          focusNode: _amountFocus,
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          style: EntryFormLayout.amount,
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            prefixText: '₹ ',
            prefixStyle: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryGreen,
            ),
            // No `0.00` placeholder: an empty field shows only the ₹ the
            // prefix carries, so a dead zero can never read as an amount.
            helperText: _strings.text(AppString.amountPrecision),
            helperStyle: EntryFormLayout.helper,
            helperMaxLines: 2,
            errorMaxLines: 4,
            errorStyle: EntryFormLayout.error,
          ),
          validator: (String? value) {
            final String text = value ?? '';
            if (parsePaise(text, allowZero: true) == null) {
              return _strings.text(AppString.amountPrecision);
            }
            if (parsePaise(text) == null) {
              return _strings.text(AppString.positiveAmount);
            }
            return null;
          },
          // The live preview and the update gate read the controller at
          // build time, so a keystroke has to repaint the screen, exactly
          // as Add Entry's amount field does.
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
  }

  Widget _dateField() {
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    final String label = widget.language == AppLanguage.bn
        ? _strings.day(_date)
        : localizations.formatMediumDate(_date);
    return InkWell(
      key: const Key('editor-date-field'),
      borderRadius: BorderRadius.circular(EntryFormLayout.frameRadius),
      onTap: _pickDate,
      child: _framed(
        child: Row(
          children: <Widget>[
            // Built here rather than const so the glyph takes the field's own
            // primary ink instead of the ambient IconTheme.
            Icon(
              Icons.calendar_today,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: EntryFormLayout.value,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: AppColors.softText),
          ],
        ),
      ),
    );
  }

  /// The categories as the same wrapping grid Add Entry uses: even columns,
  /// one row on a narrow phone, the original category always offered, and
  /// custom choices plus `More` flowing underneath in the same rhythm.
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
            for (final String category in _categoryChoices)
              if (widget.categoryStore == null ||
                  _standardCategories.contains(category))
                SizedBox(
                  width: tileWidth,
                  child: CategoryCell(
                    cellKey: Key('editor-category-$category'),
                    label: _categoryLabel(_strings, category),
                    semanticsLabel: _strings.categoryLabel(
                      _categoryLabel(_strings, category),
                    ),
                    selected: _category == category,
                    onTap: () => _selectCategory(category),
                    icon: categoryGlyph(category),
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

  Widget _descriptionField() {
    return _framed(
      focused: _descriptionFocus.hasFocus,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.edit, size: 18, color: AppColors.softText),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              label: _strings.text(AppString.description),
              child: TextFormField(
                key: const Key('editor-description-field'),
                controller: _description,
                focusNode: _descriptionFocus,
                enabled: !_busy,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 15, color: AppColors.darkText),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: _strings.text(AppString.descriptionHint),
                  hintStyle: const TextStyle(
                    fontSize: 15,
                    color: AppColors.softText,
                  ),
                  helperText: _strings.text(AppString.descriptionOptional),
                  helperStyle: EntryFormLayout.helper,
                  errorMaxLines: 4,
                  errorStyle: EntryFormLayout.error,
                ),
                validator: (String? value) =>
                    (value ?? '').trim().runes.length > 120
                    ? _strings.text(AppString.descriptionTooLong)
                    : null,
                // Repaints so the dirty check behind back protection sees
                // a description edit immediately, not at the next rebuild.
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The live one-line effect of this edit: the kind and amount about to be
  /// written, then how the khata's remaining balance moves against the
  /// stored entry, e.g. `Expense ₹999.99 → remaining +₹234.57`. The editor
  /// owns no absolute balance - its only ledger state is the original
  /// entry - so the projection is that delta: same state, same money
  /// helpers, no query. Falls back to the dash line while the amount is not
  /// a valid positive one.
  String _previewLine() {
    final int? paise = parsePaise(_amount.text);
    if (paise == null) return _strings.afterSave(null);
    final EntryFormResult original = widget.initial;
    final int effect = _kind == EntryFormKind.income ? paise : -paise;
    final int stored = original.kind == EntryFormKind.income
        ? original.amountPaise
        : -original.amountPaise;
    final String kind = _strings.text(
      _kind == EntryFormKind.income ? AppString.income : AppString.expense,
    );
    final String amount = _strings.money(paise);
    final int delta = effect - stored;
    if (delta == 0) return '$kind $amount';
    final String remaining = _strings.text(AppString.remaining).toLowerCase();
    final String sign = delta > 0 ? '+' : '';
    return '$kind $amount → $remaining $sign${_strings.money(delta)}';
  }

  /// The preview as the same calm row Add Entry puts above its save action.
  Widget _previewRow() {
    final bool hasAmount = parsePaise(_amount.text) != null;
    return Row(
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
    );
  }

  /// Update and Delete as one card: the primary action first, then a hairline
  /// and the destructive action on its own. Delete is not just a second
  /// button - the rule, the spacing and the outline all say it is different.
  Widget _saveArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.warmIvory,
        borderRadius: BorderRadius.circular(EntryFormLayout.cardRadius),
        border: Border.all(color: AppColors.beige.withValues(alpha: 0.9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FilledButton.icon(
            key: const Key('editor-update-button'),
            // Disabled until a positive amount exists: there is nothing to
            // update before that, matching Add Entry's save gate.
            onPressed: _busy || parsePaise(_amount.text) == null
                ? null
                : _submit,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  EntryFormLayout.frameRadius,
                ),
              ),
              minimumSize: const Size.fromHeight(
                EntryFormLayout.fieldMinHeight,
              ),
              disabledBackgroundColor: AppColors.beige,
              disabledForegroundColor: AppColors.softText,
            ),
            icon: const Icon(Icons.check),
            label: Text(_strings.text(AppString.updateTransaction)),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.beige),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('editor-delete-button'),
            onPressed: _busy ? null : _delete,
            style:
                OutlinedButton.styleFrom(
                  // Red text at this size would fall under AA on the cream canvas
                  // (theme.md), so the label stays darkText and the red is carried
                  // by the icon and the border. Size and shape come from the theme.
                  foregroundColor: AppColors.darkText,
                  disabledForegroundColor: AppColors.navigationGrey,
                  minimumSize: const Size.fromHeight(
                    EntryFormLayout.fieldMinHeight,
                  ),
                ).copyWith(
                  side: WidgetStateProperty.resolveWith<BorderSide?>(
                    (Set<WidgetState> states) => BorderSide(
                      color: states.contains(WidgetState.disabled)
                          ? AppColors.beige
                          : AppColors.expenseRed,
                      width: 1.2,
                    ),
                  ),
                ),
            icon: Icon(
              Icons.delete_outline,
              color: _busy ? AppColors.navigationGrey : AppColors.expenseRed,
            ),
            label: Text(_strings.text(AppString.deleteTransaction)),
          ),
        ],
      ),
    );
  }

  Widget _pendingCard(String label) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          key: const Key('editor-busy'),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.lightGreen,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.sync, size: 16, color: AppColors.primaryGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  // One line keeps the pending card out of the 500x600 test
                  // surface; long translations ellipsize instead of wrapping.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      key: const Key('editor-error'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warmIvory,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.expenseRed),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline, size: 18, color: AppColors.expenseRed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              // The full copy stays on the semantics node even when a narrow
              // layout has to ellipsize the visible line.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppColors.darkText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A blocking error, aligned under the field it belongs to.
  Widget _inlineWarning(String message) {
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

  /// A softer note (a future date can still be saved).
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

/// Discard-confirmation copy. Shared l10n has no words for this yet, so the
/// editor carries its own pair, following the [_DatePickerCopy] pattern.
enum _DiscardCopy {
  title('Discard changes?', 'পরিবর্তন বাতিল করবেন?'),
  message(
    'You have unsaved changes. Discard them and leave?',
    'আপনার অসংরক্ষিত পরিবর্তন আছে। সেগুলো বাতিল করে বেরিয়ে যাবেন?',
  ),
  keepEditing('Keep editing', 'সম্পাদনা চালিয়ে যান'),
  discard('Discard', 'বাতিল করুন');

  const _DiscardCopy(this.en, this.bn);

  final String en;
  final String bn;

  String text(AppLanguage language) => language == AppLanguage.bn ? bn : en;
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
