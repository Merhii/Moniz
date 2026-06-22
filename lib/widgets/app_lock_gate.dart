import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_lock_provider.dart';
import '../services/biometric_auth_service.dart';
import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      ref.read(appLockProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appLockProvider);
    if (state.isLoading) return const _AppLockLoadingScreen();
    if (!state.isEnabled || !state.isLocked) return widget.child;
    return const AppUnlockScreen();
  }
}

class _AppLockLoadingScreen extends StatelessWidget {
  const _AppLockLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Scaffold(
      body: DecoratedBox(
        decoration: AppTheme.brandBackground(colors),
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class AppUnlockScreen extends ConsumerStatefulWidget {
  const AppUnlockScreen({super.key});

  @override
  ConsumerState<AppUnlockScreen> createState() => _AppUnlockScreenState();
}

class _AppUnlockScreenState extends ConsumerState<AppUnlockScreen> {
  final _pinController = TextEditingController();
  var _automaticBiometricsStarted = false;
  var _isCheckingPin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
  }

  @override
  void dispose() {
    _pinController.clear();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appLockProvider);
    final colors = context.kinetic;
    return Scaffold(
      body: DecoratedBox(
        decoration: AppTheme.brandBackground(colors),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                24,
                20,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: LedgerFrame(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.lock_rounded, color: colors.accent, size: 42),
                      const SizedBox(height: 14),
                      KineticText(
                        'Moniz locked',
                        align: TextAlign.center,
                        style: AppTheme.titleStyle(
                          colors,
                        ).copyWith(fontSize: 24),
                      ),
                      const SizedBox(height: 8),
                      KineticText(
                        'Enter your 4-digit PIN to view your financial information.',
                        align: TextAlign.center,
                        muted: true,
                        uppercase: false,
                        style: AppTheme.bodyStyle(
                          colors,
                        ).copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 18),
                      _PinTextField(
                        key: const Key('app_unlock_pin'),
                        controller: _pinController,
                        label: '4-digit PIN',
                        autofocus: !state.biometricsEnabled,
                        onSubmitted: (_) => _unlockWithPin(),
                      ),
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: 10),
                        KineticText(
                          state.errorMessage!,
                          key: const Key('app_unlock_error'),
                          align: TextAlign.center,
                          uppercase: false,
                          style: AppTheme.bodyStyle(
                            colors,
                          ).copyWith(color: colors.loss, fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 14),
                      BrutalistButton(
                        key: const Key('app_unlock_submit'),
                        label: _isCheckingPin ? 'Checking...' : 'Unlock',
                        expand: true,
                        tone: BrutalistButtonTone.primary,
                        onPressed: _isCheckingPin || state.isAuthenticating
                            ? null
                            : _unlockWithPin,
                      ),
                      if (state.biometricsEnabled &&
                          state.biometricType != AppBiometricType.none) ...[
                        const SizedBox(height: 10),
                        BrutalistButton(
                          key: const Key('app_unlock_biometrics'),
                          label: state.isAuthenticating
                              ? 'Authenticating...'
                              : 'Use ${state.biometricType.label}',
                          expand: true,
                          onPressed: state.isAuthenticating
                              ? null
                              : () => ref
                                    .read(appLockProvider.notifier)
                                    .unlockWithBiometrics(),
                        ),
                      ],
                      if (state.errorMessage ==
                          'Unable to read secure app-lock settings.') ...[
                        const SizedBox(height: 10),
                        BrutalistButton(
                          key: const Key('app_lock_retry'),
                          label: 'Retry secure storage',
                          expand: true,
                          onPressed: () =>
                              ref.read(appLockProvider.notifier).initialize(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _tryBiometrics() async {
    if (!mounted || _automaticBiometricsStarted) return;
    final state = ref.read(appLockProvider);
    if (!state.biometricsEnabled ||
        state.biometricType == AppBiometricType.none) {
      return;
    }
    _automaticBiometricsStarted = true;
    await ref.read(appLockProvider.notifier).unlockWithBiometrics();
  }

  Future<void> _unlockWithPin() async {
    if (_pinController.text.length != 4 || _isCheckingPin) return;
    setState(() => _isCheckingPin = true);
    final unlocked = await ref
        .read(appLockProvider.notifier)
        .unlockWithPin(_pinController.text);
    _pinController.clear();
    if (!mounted) return;
    setState(() => _isCheckingPin = false);
    if (!unlocked) FocusScope.of(context).requestFocus();
  }
}

class _PinTextField extends StatelessWidget {
  const _PinTextField({
    super.key,
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      obscuringCharacter: '●',
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      maxLength: 4,
      textAlign: TextAlign.center,
      onSubmitted: onSubmitted,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      style: AppTheme.numberStyle(
        colors,
      ).copyWith(fontSize: 32, letterSpacing: 0),
      decoration: InputDecoration(labelText: label, counterText: ''),
    );
  }
}

Future<String?> showPinSetupDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _PinSetupDialog(),
  );
}

class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog();

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  final _pinController = TextEditingController();
  final _confirmationController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinController.clear();
    _confirmationController.clear();
    _pinController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: LedgerFrame(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KineticText(
                  'Create app PIN',
                  style: AppTheme.titleStyle(colors).copyWith(fontSize: 22),
                ),
                const SizedBox(height: 8),
                KineticText(
                  'Use exactly four digits. You will need this PIN whenever biometrics are unavailable.',
                  muted: true,
                  uppercase: false,
                  style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
                ),
                const SizedBox(height: 16),
                _PinTextField(
                  key: const Key('app_lock_new_pin'),
                  controller: _pinController,
                  label: 'New PIN',
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                _PinTextField(
                  key: const Key('app_lock_confirm_pin'),
                  controller: _confirmationController,
                  label: 'Confirm PIN',
                  onSubmitted: (_) => _save(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  KineticText(
                    _error!,
                    key: const Key('app_lock_pin_error'),
                    uppercase: false,
                    style: AppTheme.bodyStyle(
                      colors,
                    ).copyWith(color: colors.loss, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: BrutalistButton(
                        label: 'Cancel',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BrutalistButton(
                        key: const Key('app_lock_create_pin'),
                        label: 'Create PIN',
                        tone: BrutalistButtonTone.primary,
                        onPressed: _save,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _save() {
    final pin = _pinController.text;
    if (pin.length != 4) {
      setState(() => _error = 'Enter exactly four digits.');
      return;
    }
    if (_confirmationController.text != pin) {
      setState(() => _error = 'PINs do not match.');
      return;
    }
    Navigator.of(context).pop(pin);
  }
}
