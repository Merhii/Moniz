import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/money_entry.dart';
import '../models/recurring_entry.dart';
import '../providers/money_entry_provider.dart';
import '../services/currency_converter.dart';
import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';

/// What the form came back with. A rule can be saved or removed.
class RecurringFormResult {
  const RecurringFormResult.saved(this.rule) : isDeleted = false;
  const RecurringFormResult.deleted(this.rule) : isDeleted = true;

  final RecurringEntry rule;
  final bool isDeleted;
}

class RecurringEntryForm extends ConsumerStatefulWidget {
  const RecurringEntryForm({super.key, this.rule});

  final RecurringEntry? rule;

  @override
  ConsumerState<RecurringEntryForm> createState() => _RecurringEntryFormState();
}

class _RecurringEntryFormState extends ConsumerState<RecurringEntryForm> {
  late final TextEditingController _amount;
  final _amountFocus = FocusNode();
  late final TextEditingController _note;
  late MoneyDirection _direction;
  late RecurrenceFrequency _frequency;
  late int _dayOfPeriod;
  late DateTime _startsOn;
  late String _currency;
  String? _categoryId;
  String? _amountError;

  bool get _isEditing => widget.rule != null;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _amount = TextEditingController(
      text: rule == null ? '' : _trim(rule.amount),
    );
    _note = TextEditingController(text: rule?.note ?? '');
    _direction = rule?.direction ?? MoneyDirection.expense;
    _frequency = rule?.frequency ?? RecurrenceFrequency.monthly;
    _dayOfPeriod = rule?.dayOfPeriod ?? DateTime.now().day;
    _startsOn = rule?.startsOn ?? DateTime.now();
    _currency = rule?.currency ?? CurrencyConverter.defaultCurrency;
    _categoryId = rule?.categoryId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _amountFocus.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final categories = ref
        .watch(visibleMoneyCategoriesProvider)
        .where((category) => category.direction == _direction)
        .toList();

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        leading: IconButton(
          key: const Key('close_recurring_form'),
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: KineticText(
          _isEditing ? 'Edit repeat' : 'New repeat',
          style: AppTheme.titleStyle(colors).copyWith(fontSize: 22),
        ),
      ),
      body: DecoratedBox(
        decoration: AppTheme.brandBackground(colors),
        child: SafeArea(
          child: ListView(
            key: const Key('recurring_form_scroll'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _PillToggle<MoneyDirection>(
                options: MoneyDirection.values,
                selected: _direction,
                labelOf: (direction) => direction.label,
                keyOf: (direction) => Key('repeat_direction_${direction.name}'),
                onChanged: (direction) {
                  setState(() {
                    _direction = direction;
                    _categoryId = null;
                  });
                  _amountFocus.requestFocus();
                },
              ),
              const SizedBox(height: 20),
              KineticInput(
                fieldKey: const Key('repeat_amount_field'),
                controller: _amount,
                focusNode: _amountFocus,
                label: 'Amount',
                hero: true,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              if (_amountError != null) ...[
                const SizedBox(height: 8),
                KineticText(
                  _amountError!,
                  key: const Key('repeat_amount_error'),
                  uppercase: false,
                  style: AppTheme.bodyStyle(
                    colors,
                  ).copyWith(color: colors.danger, fontSize: 12),
                ),
              ],
              const SizedBox(height: 22),
              _Label(text: 'Category'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in categories)
                    _ChoiceChip(
                      key: Key('repeat_category_${category.id}'),
                      label: category.label,
                      selected: _categoryId == category.id,
                      onTap: () => setState(() => _categoryId = category.id),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              _Label(text: 'How often'),
              const SizedBox(height: 10),
              _PillToggle<RecurrenceFrequency>(
                options: RecurrenceFrequency.values,
                selected: _frequency,
                labelOf: (frequency) => frequency.label,
                keyOf: (frequency) => Key('repeat_frequency_${frequency.name}'),
                onChanged: (frequency) => setState(() {
                  _frequency = frequency;
                  // A weekday and a day of the month are different numbers, so
                  // carrying one across would silently mean something else.
                  _dayOfPeriod = frequency == RecurrenceFrequency.weekly
                      ? DateTime.now().weekday
                      : DateTime.now().day;
                }),
              ),
              const SizedBox(height: 18),
              if (_frequency == RecurrenceFrequency.weekly)
                _WeekdayPicker(
                  weekday: _dayOfPeriod,
                  onChanged: (day) => setState(() => _dayOfPeriod = day),
                )
              else
                _MonthDayPicker(
                  day: _dayOfPeriod,
                  onChanged: (day) => setState(() => _dayOfPeriod = day),
                ),
              const SizedBox(height: 18),
              KineticDatePickerTile(
                key: const Key('repeat_start_field'),
                label: 'Starts on',
                value: _formatDate(_startsOn),
                selected: true,
                onTap: _pickStart,
              ),
              const SizedBox(height: 8),
              KineticText(
                'Entries before this date are never created, and nothing is '
                'created past today.',
                muted: true,
                uppercase: false,
                style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
              ),
              const SizedBox(height: 18),
              _Label(text: 'Currency'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final currency in CurrencyConverter.recordableCurrencies)
                    _ChoiceChip(
                      key: Key('repeat_currency_$currency'),
                      label: currency,
                      selected: _currency == currency,
                      onTap: () => setState(() => _currency = currency),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              KineticInput(
                fieldKey: const Key('repeat_note_field'),
                controller: _note,
                label: 'Note',
                minLines: 1,
                maxLines: 2,
              ),
              const SizedBox(height: 28),
              BrutalistButton(
                key: const Key('repeat_save_button'),
                label: _isEditing ? 'Save' : 'Add repeat',
                tone: BrutalistButtonTone.primary,
                expand: true,
                onPressed: _submit,
              ),
              if (_isEditing) ...[
                const SizedBox(height: 12),
                BrutalistButton(
                  key: const Key('repeat_delete_button'),
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

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsOn,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null) return;
    setState(() => _startsOn = picked);
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
      setState(() => _amountError = 'Amount must be more than zero');
      return;
    }

    final note = _note.text.trim();
    Navigator.of(context).pop(
      RecurringFormResult.saved(
        RecurringEntry(
          id: widget.rule?.id ?? const Uuid().v4(),
          amount: amount,
          direction: _direction,
          currency: _currency,
          categoryId: _categoryId,
          accountId: widget.rule?.accountId ?? MoneyAccount.defaultId,
          note: note.isEmpty ? null : note,
          frequency: _frequency,
          dayOfPeriod: _dayOfPeriod,
          startsOn: _startsOn,
          lastRunOn: widget.rule?.lastRunOn,
          isPaused: widget.rule?.isPaused ?? false,
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final rule = widget.rule;
    if (rule == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this repeat?'),
        content: const Text(
          'It will stop creating new entries. Entries it already created stay '
          'in your ledger.',
        ),
        actions: [
          TextButton(
            key: const Key('cancel_delete_repeat'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirm_delete_repeat'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop(RecurringFormResult.deleted(rule));
  }

  static String _trim(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}'
        '-${date.day.toString().padLeft(2, '0')}';
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return KineticText(
      text,
      style: AppTheme.labelStyle(context.kinetic).copyWith(fontSize: 12),
    );
  }
}

class _PillToggle<T> extends StatelessWidget {
  const _PillToggle({
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.keyOf,
    required this.onChanged,
  });

  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final Key Function(T) keyOf;
  final ValueChanged<T> onChanged;

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
          for (final option in options)
            Expanded(
              child: GestureDetector(
                key: keyOf(option),
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(option),
                child: AnimatedContainer(
                  duration: AppTheme.fast,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: selected == option
                        ? colors.accent
                        : Colors.transparent,
                    borderRadius: AppTheme.pillRadius,
                  ),
                  child: Center(
                    child: KineticText(
                      labelOf(option),
                      style: AppTheme.labelStyle(colors).copyWith(
                        color: selected == option
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

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
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

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.weekday, required this.onChanged});

  final int weekday;
  final ValueChanged<int> onChanged;

  static const _labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var day = 1; day <= 7; day++)
          _ChoiceChip(
            key: Key('repeat_weekday_$day'),
            label: _labels[day - 1],
            selected: weekday == day,
            onTap: () => onChanged(day),
          ),
      ],
    );
  }
}

class _MonthDayPicker extends StatelessWidget {
  const _MonthDayPicker({required this.day, required this.onChanged});

  final int day;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KineticDropdown<int>(
          key: const Key('repeat_month_day'),
          label: 'Day of the month',
          value: day,
          items: [for (var value = 1; value <= 31; value++) value],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
          itemLabelBuilder: (value) => RecurringEntry(
            id: '',
            amount: 0,
            direction: MoneyDirection.expense,
            frequency: RecurrenceFrequency.monthly,
            dayOfPeriod: value,
            startsOn: DateTime.now(),
          ).scheduleLabel.replaceFirst('Every month on the ', ''),
        ),
        if (day > 28) ...[
          const SizedBox(height: 8),
          KineticText(
            'Months without a ${day}th use their last day instead.',
            key: const Key('repeat_clamp_note'),
            muted: true,
            uppercase: false,
            style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
          ),
        ],
      ],
    );
  }
}
