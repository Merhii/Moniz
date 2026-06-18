import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_lock_provider.dart';
import '../services/biometric_auth_service.dart';
import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';
import 'app_lock_gate.dart';

class SecuritySettingsCard extends ConsumerWidget {
  const SecuritySettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appLockProvider);
    final colors = context.kinetic;
    return LedgerFrame(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KineticText('SECURITY', style: AppTheme.labelStyle(colors)),
                    const SizedBox(height: 7),
                    KineticText(
                      state.isEnabled ? 'APP LOCK ON' : 'APP LOCK OFF',
                      key: const Key('app_lock_status'),
                      style: AppTheme.displayStyle(
                        colors,
                      ).copyWith(fontSize: 30),
                    ),
                  ],
                ),
              ),
              BrutalistButton(
                key: Key(
                  state.isEnabled ? 'disable_app_lock' : 'enable_app_lock',
                ),
                label: state.isEnabled ? 'DISABLE' : 'ENABLE',
                tone: state.isEnabled
                    ? BrutalistButtonTone.danger
                    : BrutalistButtonTone.primary,
                onPressed: state.isLoading
                    ? null
                    : () => state.isEnabled
                          ? _disable(context, ref)
                          : _enable(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 10),
          KineticText(
            state.isEnabled
                ? 'MONIZ locks whenever the app leaves the foreground.'
                : 'Require a secure 4-digit PIN when opening or returning to MONIZ.',
            muted: true,
            uppercase: false,
            style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
          ),
          if (state.isEnabled) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              decoration: BoxDecoration(
                color: colors.background.withValues(alpha: 0.42),
                borderRadius: AppTheme.tightRadius,
                border: Border.all(
                  color: colors.border,
                  width: AppTheme.thickBorderWidth,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    state.biometricType == AppBiometricType.faceId
                        ? Icons.face_rounded
                        : Icons.fingerprint_rounded,
                    color: state.biometricType == AppBiometricType.none
                        ? colors.mutedForeground
                        : colors.accent,
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        KineticText(
                          state.biometricType.label,
                          style: AppTheme.titleStyle(
                            colors,
                          ).copyWith(fontSize: 18),
                        ),
                        const SizedBox(height: 4),
                        KineticText(
                          state.biometricType == AppBiometricType.none
                              ? 'Not available or not enrolled on this device.'
                              : 'PIN remains available as the fallback.',
                          muted: true,
                          uppercase: false,
                          style: AppTheme.bodyStyle(
                            colors,
                          ).copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    key: const Key('app_lock_biometrics_toggle'),
                    value: state.biometricsEnabled,
                    onChanged:
                        state.biometricType == AppBiometricType.none ||
                            state.isAuthenticating
                        ? null
                        : (enabled) => ref
                              .read(appLockProvider.notifier)
                              .setBiometricsEnabled(enabled),
                    activeThumbColor: colors.accentForeground,
                    activeTrackColor: colors.accent,
                  ),
                ],
              ),
            ),
          ],
          if (state.errorMessage != null) ...[
            const SizedBox(height: 10),
            KineticText(
              state.errorMessage!,
              key: const Key('app_lock_settings_error'),
              uppercase: false,
              style: AppTheme.bodyStyle(
                colors,
              ).copyWith(color: colors.loss, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _enable(BuildContext context, WidgetRef ref) async {
    final pin = await showPinSetupDialog(context);
    if (pin == null || !context.mounted) return;
    try {
      await ref.read(appLockProvider.notifier).enable(pin);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to enable app lock.')),
      );
    }
  }

  Future<void> _disable(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disable app lock?'),
        content: const Text(
          'MONIZ will stop asking for your PIN or biometrics when the app resumes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirm_disable_app_lock'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(appLockProvider.notifier).disable();
  }
}
