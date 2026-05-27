import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/asset.dart';

class AssetFormDialog extends StatefulWidget {
  const AssetFormDialog({super.key, this.asset});

  final Asset? asset;

  @override
  State<AssetFormDialog> createState() => _AssetFormDialogState();
}

class _AssetFormDialogState extends State<AssetFormDialog> {
  static const _currencies = ['USD', 'EUR', 'AED'];
  static const _typeOptions = <_MenuOption<AssetType>>[
    _MenuOption(
      value: AssetType.cash,
      label: 'Cash',
      icon: Icons.payments_outlined,
      key: Key('asset_type_cash'),
    ),
    _MenuOption(
      value: AssetType.gold,
      label: 'Gold',
      icon: Icons.workspace_premium_outlined,
      key: Key('asset_type_gold'),
    ),
    _MenuOption(
      value: AssetType.silver,
      label: 'Silver',
      icon: Icons.circle_outlined,
      key: Key('asset_type_silver'),
    ),
  ];
  static const _currencyOptions = <_MenuOption<String>>[
    _MenuOption(
      value: 'USD',
      label: 'USD',
      icon: Icons.attach_money,
      key: Key('asset_currency_usd'),
    ),
    _MenuOption(
      value: 'AED',
      label: 'AED',
      icon: Icons.account_balance_wallet_outlined,
      key: Key('asset_currency_aed'),
    ),
    _MenuOption(
      value: 'EUR',
      label: 'EUR',
      icon: Icons.euro,
      key: Key('asset_currency_eur'),
    ),
  ];
  static const _tagOptions = <_MenuOption<AssetTag?>>[
    _MenuOption(
      value: null,
      label: 'No tag',
      icon: Icons.label_off_outlined,
      key: Key('asset_tag_none'),
    ),
    _MenuOption(
      value: AssetTag.freelance,
      label: 'Freelance',
      icon: Icons.laptop_mac_outlined,
      key: Key('asset_tag_freelance'),
    ),
    _MenuOption(
      value: AssetTag.emergency,
      label: 'Emergency',
      icon: Icons.warning_amber_outlined,
      key: Key('asset_tag_emergency'),
    ),
    _MenuOption(
      value: AssetTag.gift,
      label: 'Gift',
      icon: Icons.card_giftcard,
      key: Key('asset_tag_gift'),
    ),
    _MenuOption(
      value: AssetTag.salary,
      label: 'Salary',
      icon: Icons.payments_outlined,
      key: Key('asset_tag_salary'),
    ),
    _MenuOption(
      value: AssetTag.businessProfit,
      label: 'Business Profit',
      icon: Icons.trending_up,
      key: Key('asset_tag_business_profit'),
    ),
  ];
  static const _goldPurityOptions = <_MenuOption<double>>[
    _MenuOption(
      value: 99.9,
      label: '24K',
      detail: '99.9%',
      icon: Icons.workspace_premium_outlined,
      key: Key('asset_purity_gold_24k'),
    ),
    _MenuOption(
      value: 91.7,
      label: '22K',
      detail: '91.7%',
      icon: Icons.workspace_premium_outlined,
      key: Key('asset_purity_gold_22k'),
    ),
    _MenuOption(
      value: 75,
      label: '18K',
      detail: '75%',
      icon: Icons.workspace_premium_outlined,
      key: Key('asset_purity_gold_18k'),
    ),
  ];
  static const _silverPurityOptions = <_MenuOption<double>>[
    _MenuOption(
      value: 99.5,
      label: '99.5%',
      detail: 'Fine silver',
      icon: Icons.circle_outlined,
      key: Key('asset_purity_silver_995'),
    ),
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _boughtPriceController;
  late final TextEditingController _soldPriceController;
  late final TextEditingController _notesController;
  late AssetType _selectedType;
  late String _selectedCurrency;
  AssetTag? _selectedTag;
  double? _selectedPurity;
  DateTime? _boughtDate;
  DateTime? _soldDate;
  late bool _isSold;
  String? _dateError;
  String? _purityError;

  bool get _isEditing => widget.asset != null;
  bool get _isMetal => _selectedType.isMetal;

  @override
  void initState() {
    super.initState();
    final asset = widget.asset;
    _selectedType = asset?.type ?? AssetType.cash;
    _selectedCurrency = _currencies.contains(asset?.currency)
        ? asset!.currency
        : 'USD';
    _selectedTag = asset?.tag;
    _selectedPurity = asset?.purity;
    _amountController = TextEditingController(text: _numberText(asset?.amount));
    _boughtPriceController = TextEditingController(
      text: _numberText(asset?.boughtPrice),
    );
    _soldPriceController = TextEditingController(
      text: _numberText(asset?.soldPrice),
    );
    _notesController = TextEditingController(text: asset?.note ?? '');
    _boughtDate = asset?.boughtDate;
    _soldDate = asset?.soldDate;
    _isSold = asset?.soldDate != null || asset?.soldPrice != null;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _boughtPriceController.dispose();
    _soldPriceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit Asset' : 'Add Asset'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SelectionMenu<AssetType>(
                  key: const Key('asset_type_field'),
                  label: 'Asset Type',
                  options: _availableTypeOptions,
                  value: _selectedType,
                  onChanged: _setType,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('asset_amount_field'),
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _isMetal ? 'Weight (grams)' : 'Amount',
                  ),
                  validator: (value) => _requiredPositiveNumber(
                    value,
                    _isMetal ? 'Weight' : 'Amount',
                  ),
                ),
                const SizedBox(height: 12),
                _SelectionMenu<String>(
                  key: const Key('asset_currency_field'),
                  label: _isMetal ? 'Price Currency' : 'Currency',
                  options: _currencyOptions,
                  value: _selectedCurrency,
                  onChanged: (currency) {
                    setState(() => _selectedCurrency = currency);
                  },
                ),
                const SizedBox(height: 12),
                _SelectionMenu<AssetTag?>(
                  key: const Key('asset_tag_field'),
                  label: 'Tag',
                  options: _tagOptions,
                  value: _selectedTag,
                  onChanged: (tag) {
                    setState(() => _selectedTag = tag);
                  },
                ),
                const SizedBox(height: 12),
                _DateField(
                  label: 'Holding Start Date',
                  date: _boughtDate,
                  onTap: () => _selectDate(isBoughtDate: true),
                  onClear: () => _clearDate(isBoughtDate: true),
                ),
                if (_isMetal) ...[
                  const SizedBox(height: 12),
                  _SelectionMenu<double>(
                    key: const Key('asset_purity_field'),
                    label: 'Purity',
                    options: _availablePurityOptions,
                    value: _selectedPurity,
                    onChanged: (purity) {
                      setState(() {
                        _selectedPurity = purity;
                        _purityError = null;
                      });
                    },
                  ),
                  if (_purityError != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _purityError!,
                        key: const Key('asset_purity_error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('asset_bought_price_field'),
                    controller: _boughtPriceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Bought Price ($_selectedCurrency)',
                    ),
                    validator: _validateBoughtPrice,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const Key('asset_is_sold_toggle'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('This asset has been sold'),
                    subtitle: const Text(
                      'Turn this on only when recording a completed sale.',
                    ),
                    value: _isSold,
                    onChanged: _setSold,
                  ),
                  if (_isSold) ...[
                    const SizedBox(height: 12),
                    _DateField(
                      label: 'Sold Date',
                      date: _soldDate,
                      onTap: () => _selectDate(isBoughtDate: false),
                      onClear: () => _clearDate(isBoughtDate: false),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('asset_sold_price_field'),
                      controller: _soldPriceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Sold Price ($_selectedCurrency)',
                      ),
                      validator: _validateSoldPrice,
                    ),
                  ],
                  if (_dateError != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _dateError!,
                        key: const Key('asset_date_error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('asset_notes_field'),
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  minLines: 2,
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('asset_save_button'),
          onPressed: _save,
          child: Text(_isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  Future<void> _selectDate({required bool isBoughtDate}) async {
    final initialDate = isBoughtDate ? _boughtDate : _soldDate;
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (selectedDate == null) return;

    setState(() {
      if (isBoughtDate) {
        _boughtDate = selectedDate;
      } else {
        _soldDate = selectedDate;
      }
      _dateError = null;
    });
    _formKey.currentState?.validate();
  }

  void _save() {
    final hasValidFields = _formKey.currentState!.validate();
    final dateError = _validateDates();
    final purityError = _isMetal ? _validateSelectedPurity() : null;
    setState(() {
      _dateError = dateError;
      _purityError = purityError;
    });
    if (!hasValidFields || dateError != null || purityError != null) return;

    final note = _notesController.text.trim();
    final asset = Asset(
      id: widget.asset?.id ?? const Uuid().v4(),
      type: _selectedType,
      amount: double.parse(_amountController.text.trim()),
      unit: _isMetal ? 'g' : _selectedCurrency,
      currency: _selectedCurrency,
      tag: _selectedTag,
      purity: _isMetal ? _selectedPurity : null,
      boughtDate: _boughtDate,
      boughtPrice: _isMetal
          ? _optionalNumber(_boughtPriceController.text)
          : null,
      soldDate: _isMetal && _isSold ? _soldDate : null,
      soldPrice: _isMetal && _isSold
          ? _optionalNumber(_soldPriceController.text)
          : null,
      note: note.isEmpty ? null : note,
    );

    Navigator.pop(context, asset);
  }

  String? _requiredPositiveNumber(String? value, String label) {
    final trimmedValue = value?.trim() ?? '';
    if (trimmedValue.isEmpty) return '$label is required';
    final number = double.tryParse(trimmedValue);
    if (number == null) return '$label must be numeric';
    if (number <= 0) return '$label must be greater than zero';
    return null;
  }

  String? _validateSelectedPurity() {
    final purity = _selectedPurity;
    if (purity == null) return 'Select a purity';
    if (purity <= 0 || purity > 100) {
      return 'Purity must be between 0 and 100';
    }
    return null;
  }

  String? _validateBoughtPrice(String? value) {
    final valueError = _optionalNonNegativeNumber(value, 'Bought price');
    if (valueError != null) return valueError;
    if ((value?.trim().isNotEmpty ?? false) && _boughtDate == null) {
      return 'Select a bought date for this price';
    }
    return null;
  }

  String? _validateSoldPrice(String? value) {
    if (!_isSold) return null;
    final valueError = _optionalNonNegativeNumber(value, 'Sold price');
    if (valueError != null) return valueError;
    final hasPrice = value?.trim().isNotEmpty ?? false;
    if (hasPrice && _soldDate == null) {
      return 'Select a sold date for this price';
    }
    if (_soldDate != null && !hasPrice) {
      return 'Sold price is required when sold date is set';
    }
    return null;
  }

  String? _validateDates() {
    if (!_isMetal || !_isSold || _soldDate == null) return null;
    if (_boughtDate == null) {
      return 'Select a bought date before marking this asset sold';
    }
    if (_soldDate!.isBefore(_boughtDate!)) {
      return 'Sold date cannot be before bought date';
    }
    return null;
  }

  void _clearDate({required bool isBoughtDate}) {
    setState(() {
      if (isBoughtDate) {
        _boughtDate = null;
      } else {
        _soldDate = null;
      }
      _dateError = null;
    });
    _formKey.currentState?.validate();
  }

  void _setSold(bool sold) {
    setState(() {
      _isSold = sold;
      _dateError = null;
      if (!sold) {
        _soldDate = null;
        _soldPriceController.clear();
      }
    });
    _formKey.currentState?.validate();
  }

  void _setType(AssetType type) {
    setState(() {
      _selectedType = type;
      _dateError = null;
      _purityError = null;
      if (!type.isMetal) {
        _selectedPurity = null;
        _isSold = false;
        _soldDate = null;
        _soldPriceController.clear();
      } else {
        final options = type == AssetType.gold
            ? _goldPurityOptions
            : _silverPurityOptions;
        if (!options.any((option) => option.value == _selectedPurity)) {
          _selectedPurity = options.first.value;
        }
      }
    });
  }

  List<_MenuOption<AssetType>> get _availableTypeOptions {
    if (_selectedType != AssetType.bankSavings) return _typeOptions;
    return [
      ..._typeOptions,
      const _MenuOption(
        value: AssetType.bankSavings,
        label: 'Bank Savings',
        detail: 'Existing',
        icon: Icons.account_balance_outlined,
        key: Key('asset_type_bank_savings_existing'),
      ),
    ];
  }

  List<_MenuOption<double>> get _availablePurityOptions {
    final standardOptions = _selectedType == AssetType.gold
        ? _goldPurityOptions
        : _silverPurityOptions;
    final selectedPurity = _selectedPurity;
    final isValidLegacyPurity =
        selectedPurity != null &&
        selectedPurity > 0 &&
        selectedPurity <= 100 &&
        !standardOptions.any((option) => option.value == selectedPurity) &&
        widget.asset?.type == _selectedType;
    if (!isValidLegacyPurity) return standardOptions;

    return [
      ...standardOptions,
      _MenuOption(
        value: selectedPurity,
        label: '${_numberText(selectedPurity)}%',
        detail: 'Existing',
        icon: Icons.history,
        key: const Key('asset_purity_existing'),
      ),
    ];
  }

  String? _optionalNonNegativeNumber(String? value, String label) {
    final trimmedValue = value?.trim() ?? '';
    if (trimmedValue.isEmpty) return null;
    final number = double.tryParse(trimmedValue);
    if (number == null) return '$label must be numeric';
    if (number < 0) return '$label cannot be negative';
    return null;
  }

  double? _optionalNumber(String value) {
    final trimmedValue = value.trim();
    return trimmedValue.isEmpty ? null : double.parse(trimmedValue);
  }

  String _numberText(double? value) {
    if (value == null) return '';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}

class _MenuOption<T> {
  const _MenuOption({
    required this.value,
    required this.label,
    required this.icon,
    required this.key,
    this.detail,
  });

  final T value;
  final String label;
  final String? detail;
  final IconData icon;
  final Key key;
}

class _SelectionMenu<T> extends StatelessWidget {
  const _SelectionMenu({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.columns = 3,
  });

  final String label;
  final List<_MenuOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final hasDetails = options.any((option) => option.detail != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            final itemWidth =
                (constraints.maxWidth - (gap * (columns - 1))) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: options
                  .map(
                    (option) => SizedBox(
                      width: itemWidth,
                      child: _SelectionMenuItem<T>(
                        option: option,
                        selected: value == option.value,
                        showDetail: hasDetails,
                        onTap: () => onChanged(option.value),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _SelectionMenuItem<T> extends StatelessWidget {
  const _SelectionMenuItem({
    required this.option,
    required this.selected,
    required this.showDetail,
    required this.onTap,
  });

  final _MenuOption<T> option;
  final bool selected;
  final bool showDetail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: option.key,
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: showDetail ? 88 : 72,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? colors.primary.withValues(alpha: 0.14)
                : colors.surfaceContainerHighest.withValues(alpha: 0.35),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                option.icon,
                size: 22,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
              if (showDetail)
                Text(
                  option.detail ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Expanded(child: Text(date == null ? 'Not set' : _formatDate(date!))),
          TextButton(
            onPressed: onTap,
            child: Text(date == null ? 'Select' : 'Change'),
          ),
          if (date != null)
            IconButton(
              tooltip: 'Clear date',
              onPressed: onClear,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}
