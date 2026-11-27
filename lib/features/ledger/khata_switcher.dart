// Flutter material migration is tracked separately.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import 'data/local_ledger.dart';

/// The card language of every other ledger surface, so the sheet, its dialog
/// and the rows inside it are cut from the same cloth: one card radius, one
/// smaller radius for a row, one gap and one 1 px rule.
const double _cardRadius = 20;
const double _rowRadius = 16;
const double _gap = 12;
const double _separator = 1;

/// The same caption / row-title / card-title steps Home and the ledger screens
/// use, and the same flat tile shape every row gets.
const double _labelSize = 12;
const double _rowTitleSize = 15;
const double _cardTitleSize = 16;

const RoundedRectangleBorder _tileShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(_rowRadius)),
);

/// Choosing a khata is session-only; ledger contents always remain on device.
///
/// [language] localizes the switcher, its rows and the create dialog. Khata
/// names are the user's own text and are always shown verbatim; English stays
/// the default so an unwired call site reads exactly as before.
Future<LocalKhata?> showKhataSwitcher(
  BuildContext context,
  LocalLedger ledger,
  List<LocalKhata> khatas,
  String activeId, {
  AppLanguage language = AppLanguage.en,
  Future<void> Function()? onManage,
}) async {
  final AppStrings strings = AppStrings(language);
  final String? choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(_cardRadius)),
    ),
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(_gap, 0, _gap, _gap),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(_gap, 4, _gap, _labelSize),
            child: Text(
              strings.text(AppString.chooseKhata),
              style: const TextStyle(
                fontSize: _cardTitleSize,
                height: 1.3,
                letterSpacing: -0.1,
                fontWeight: FontWeight.w700,
                color: AppColors.darkText,
              ),
            ),
          ),
          // The active khata is the selected one, so it wears the same
          // lightGreen tile, bold green label and check mark the entry form
          // uses for a chosen category: emphasis by fill, type and a mark.
          for (final khata in khatas)
            ListTile(
              key: Key('khata-${khata.id}'),
              selected: khata.id == activeId,
              shape: _tileShape,
              tileColor: khata.id == activeId ? AppColors.lightGreen : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: _gap,
                vertical: 4,
              ),
              title: Text(
                khata.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _rowTitleSize,
                  height: 1.3,
                  fontWeight: khata.id == activeId
                      ? FontWeight.w700
                      : FontWeight.w600,
                  color: khata.id == activeId
                      ? AppColors.primaryGreen
                      : AppColors.darkText,
                ),
              ),
              trailing: khata.id == activeId
                  ? const Icon(Icons.check, color: AppColors.primaryGreen)
                  : null,
              onTap: () => Navigator.pop(context, khata.id),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: _gap),
            child: SizedBox(
              height: _separator,
              child: ColoredBox(color: AppColors.beige),
            ),
          ),
          ListTile(
            key: const Key('new-khata'),
            shape: _tileShape,
            contentPadding: const EdgeInsets.symmetric(horizontal: _gap),
            leading: const Icon(Icons.add, color: AppColors.primaryGreen),
            title: Text(
              strings.text(AppString.newKhata),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: _rowTitleSize,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: AppColors.darkText,
              ),
            ),
            onTap: () => Navigator.pop(context, '__new__'),
          ),
          if (onManage != null)
            ListTile(
              key: const Key('manage-khatas'),
              shape: _tileShape,
              contentPadding: const EdgeInsets.symmetric(horizontal: _gap),
              leading: const Icon(
                Icons.manage_accounts_outlined,
                color: AppColors.softText,
              ),
              title: Text(
                strings.text(AppString.manageKhatas),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: _rowTitleSize,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkText,
                ),
              ),
              onTap: () => Navigator.pop(context, '__manage__'),
            ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;
  if (choice == '__manage__') {
    await onManage?.call();
    return null;
  }
  if (choice != '__new__') return khatas.firstWhere((k) => k.id == choice);
  return showDialog<LocalKhata>(
    context: context,
    builder: (_) => _CreateKhata(ledger: ledger, language: language),
  );
}

class _CreateKhata extends StatefulWidget {
  const _CreateKhata({required this.ledger, required this.language});

  final LocalLedger ledger;
  final AppLanguage language;

  @override
  State<_CreateKhata> createState() => _CreateKhataState();
}

class _CreateKhataState extends State<_CreateKhata> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _opening = TextEditingController(text: '0');
  bool _saving = false;
  String? _error;

  AppStrings get _strings => AppStrings(widget.language);

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  /// 1-40 characters after trimming, with the message in the active language.
  String? _validateName(String? value) {
    final String name = value?.trim() ?? '';
    if (name.isEmpty || name.runes.length > 40) {
      return _strings.text(AppString.nameUpTo40);
    }
    return null;
  }

  /// 0 to 999999999.99 with at most two decimals, in the active language.
  String? _validateOpening(String? value) {
    if (_paise(value ?? '') == null) {
      return _strings.text(AppString.openingBalanceRange);
    }
    return null;
  }

  /// Zero is a fine opening balance, and the field starts out as `0`, so a
  /// leading zero in front of what is typed (`05000`) has to be fine too.
  int? _paise(String input) =>
      parsePaise(input, allowZero: true, allowLeadingZeros: true);

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final khata = await widget.ledger.createKhata(
        name: _name.text,
        openingBalancePaise: _paise(_opening.text)!,
      );
      if (mounted) Navigator.pop(context, khata);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _strings.text(AppString.createKhataFailed);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = _strings;
    return AlertDialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(_cardRadius)),
      ),
      title: Text(
        strings.text(AppString.newKhata),
        style: const TextStyle(
          fontSize: _cardTitleSize,
          height: 1.3,
          letterSpacing: -0.1,
          fontWeight: FontWeight.w700,
          color: AppColors.darkText,
        ),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                key: const Key('khata-name'),
                controller: _name,
                maxLength: 40,
                decoration: InputDecoration(
                  labelText: strings.text(AppString.khataName),
                ),
                validator: _validateName,
              ),
              TextFormField(
                key: const Key('khata-opening'),
                controller: _opening,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: strings.text(AppString.openingBalanceInput),
                ),
                validator: _validateOpening,
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(strings.text(AppString.cancel)),
        ),
        FilledButton(
          key: const Key('create-khata'),
          onPressed: _saving ? null : _save,
          child: Text(strings.text(AppString.create)),
        ),
      ],
    );
  }
}
