import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/money_entry.dart';
import '../providers/money_entry_provider.dart';
import '../services/currency_converter.dart';
import '../services/money_ledger.dart';
import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';

/// What capture came back with. An entry can be saved or removed, and the
/// caller has to be able to tell which without inspecting the entry.
class MoneyCaptureResult {
  const MoneyCaptureResult.saved(this.entry) : isDeleted = false;
  const MoneyCaptureResult.deleted(this.entry) : isDeleted = true;

  final MoneyEntry entry;
  final bool isDeleted;
}

/// Logging a spend has a budget of three taps and one number, so everything
/// except the amount and the category is defaulted and tucked behind a
/// disclosure. Trackers are abandoned over exactly this.
class MoneyCaptureSheet extends ConsumerStatefulWidget {
  const MoneyCaptureSheet({super.key, this.entry});

  /// Editing an existing entry rather than logging a new one.
  final MoneyEntry? entry;

  @override
  ConsumerState<MoneyCaptureSheet> createState() => _MoneyCaptureSheetState();
}

class _MoneyCaptureSheetState extends ConsumerState<MoneyCaptureSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late MoneyDirection _direction;
  late DateTime _happenedAt;
  late String _currency;
  String? _categoryId;
  String? _amountError;
  var _showsMore = false;

  bool get _isEditing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _amount = TextEditingController(
      text: entry == null ? '' : _trim(entry.amount),
    );
    _note = TextEditingController(text: entry?.note ?? '');
    // Most entries are money going out, so that is where the form starts.
    _direction = entry?.direction ?? MoneyDirection.expense;
    _happenedAt = entry?.happenedAt ?? DateTime.now();
    _currency = entry?.currency ?? CurrencyConverter.defaultCurrency;
    _categoryId = entry?.categoryId;
    _showsMore = _isEditing;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final entries = ref.watch(moneyEntryProvider);
    final categories = MoneyLedger.byRecentUse(
      ref.watch(moneyCategoryProvider),
      entries,
      direction: _direction,
    );

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        leading: IconButton(
          key: const Key('close_money_capture'),
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: KineticText(
          _isEditing ? 'Edit entry' : 'Add entry',
          style: AppTheme.titleStyle(colors).copyWith(fontSize: 22),
        ),
        centerTitle: true,
      ),
      body: DecoratedBox(
        decoration: AppTheme.brandBackground(colors),
        child: SafeArea(
          child: ListView(
            key: const Key('money_capture_scroll'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _DirectionToggle(
                direction: _direction,
                onChanged: (direction) => setState(() {
                  _direction = direction;
                  _categoryId = null;
                }),
              ),
              const SizedBox(height: 20),
              KineticInput(
                fieldKey: const Key('money_amount_field'),
                controller: _amount,
                label: 'Amount',
                hero: true,
                // Opens with the keyboard up and the cursor here, so the
                // three taps are capture, category, save — not four.
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              if (_amountError != null) ...[
                const SizedBox(height: 8),
                KineticText(
                  _amountError!,
                  key: const Key('money_amount_error'),
                  uppercase: false,
                  style: AppTheme.bodyStyle(
                    colors,
                  ).copyWith(color: colors.danger, fontSize: 12),
                ),
              ],
              const SizedBox(height: 22),
              KineticText(
                'Category',
                style: AppTheme.labelStyle(colors).copyWith(fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in categories)
                    _CategoryChip(
                      key: Key('money_category_${category.id}'),
                      label: category.label,
                      selected: _categoryId == category.id,
                      onTap: () =>
                          setState(() => _categoryId = category.id),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (!_showsMore)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('money_capture_more'),
                    onPressed: () => setState(() => _showsMore = true),
                    child: KineticText(
                      'Date, currency and note',
                      uppercase: false,
                      style: AppTheme.bodyStyle(
                        colors,
                      ).copyWith(color: colors.accent, fontSize: 13),
                    ),
                  ),
                )
              else ...[
                KineticDatePickerTile(
                  key: const Key('money_date_field'),
                  label: 'Date',
                  value: _formatDate(_happenedAt),
                  selected: true,
                  onTap: _pickDate,
                ),
                const SizedBox(height: 16),
                KineticText(
                  'Currency',
                  style: AppTheme.labelStyle(colors).copyWith(fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final currency
                        in CurrencyConverter.recordableCurrencies)
                      _CategoryChip(
                        key: Key('money_currency_$currency'),
                        label: currency,
                        selected: _currency == currency,
                        onTap: () => setState(() => _currency = currency),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                KineticInput(
                  fieldKey: const Key('money_note_field'),
                  controller: _note,
                  label: 'Note',
                  maxLines: 2,
                  minLines: 1,
                ),
              ],
              const SizedBox(height: 28),
              BrutalistButton(
                key: const Key('money_save_button'),
                label: _isEditing ? 'Save' : 'Add',
                tone: BrutalistButtonTone.primary,
                expand: true,
                onPressed: _submit,
              ),
              // Delete lives where you already are when you noticed the entry
              // was wrong, rather than behind a gesture you have to know about.
              if (_isEditing) ...[
                const SizedBox(height: 12),
                BrutalistButton(
                  key: const Key('money_delete_button'),
                  label: 'Delete',
                  tone: BrutalistButtonTone.danger,
                  expand: true,
                  onPressed: _confirmDelete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _happenedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _happenedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _happenedAt.hour,
        _happenedAt.minute,
      );
    });
  }

  void _submit() {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (amount == null || amount.isNaN) {
      setState(() => _amountError = 'Enter an amount');
      return;
    }
    if (!amount.isFinite) {
      setState(() => _amountError = 'That amount is too large');
      return;
    }
    if (amount <= 0) {
      // Direction already says which way the money went, so a negative here
      // would be a second, contradictory answer to the same question.
      setState(() => _amountError = 'Amount must be more than zero');
      return;
    }

    final note = _note.text.trim();
    Navigator.of(context).pop(
      MoneyCaptureResult.saved(
        MoneyEntry(
          id: widget.entry?.id ?? const Uuid().v4(),
          amount: amount,
          direction: _direction,
          currency: _currency,
          happenedAt: _happenedAt,
          accountId: widget.entry?.accountId ?? MoneyAccount.defaultId,
          categoryId: _categoryId,
          note: note.isEmpty ? null : note,
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final entry = widget.entry;
    if (entry == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text(
          'It will be removed from your totals permanently. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            key: const Key('cancel_delete_entry'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirm_delete_entry'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop(MoneyCaptureResult.deleted(entry));
  }

  static String _trim(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  static String _formatDate(DateTime date) {
    final today = DateTime.now();
    if (date.year == today.year &&
        date.month == today.month &&
        date.day == today.day) {
      return 'Today';
    }
    return '${date.year}-${date.month.toString().padLeft(2, '0')}'
        '-${date.day.toString().padLeft(2, '0')}';
  }
}

class _DirectionToggle extends StatelessWidget {
  const _DirectionToggle({required this.direction, required this.onChanged});

  final MoneyDirection direction;
  final ValueChanged<MoneyDirection> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.foreground.withValues(alpha: 0.04),
        borderRadius: AppTheme.pillRadius,
        border: Border.all(color: colors.border.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          for (final option in MoneyDirection.values)
            Expanded(
              child: GestureDetector(
                key: Key('money_direction_${option.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(option);
                },
                child: AnimatedContainer(
                  duration: AppTheme.fast,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: direction == option
                        ? colors.accent
                        : Colors.transparent,
                    borderRadius: AppTheme.pillRadius,
                  ),
                  child: Center(
                    child: KineticText(
                      option.label,
                      style: AppTheme.labelStyle(colors).copyWith(
                        color: direction == option
                            ? colors.accentForeground
                            : colors.mutedForeground,
                        fontSize: 13,
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
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTheme.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? colors.accent.withValues(alpha: 0.18)
              : colors.foreground.withValues(alpha: 0.03),
          borderRadius: AppTheme.pillRadius,
          border: Border.all(
            color: selected
                ? colors.accent
                : colors.border.withValues(alpha: 0.2),
          ),
        ),
        child: KineticText(
          label,
          uppercase: false,
          style: AppTheme.bodyStyle(colors).copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? colors.accent : colors.foreground,
          ),
        ),
      ),
    );
  }
}
