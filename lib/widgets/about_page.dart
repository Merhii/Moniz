import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';

const _supportUrl = 'https://github.com/Merhii/Moniz/issues';
const currentAppVersion = AppVersionInfo(version: '1.0.0', buildNumber: '1');

class AppVersionInfo {
  const AppVersionInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;
}

Future<AppVersionInfo> loadAppVersion() async {
  return currentAppVersion;
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.versionLoader = loadAppVersion});

  final Future<AppVersionInfo> Function() versionLoader;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final Future<AppVersionInfo> _version;

  @override
  void initState() {
    super.initState();
    _version = widget.versionLoader();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return CustomScrollView(
      key: const Key('about_scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KineticText(
                  'About MONIZ',
                  style: AppTheme.titleStyle(
                    colors,
                  ).copyWith(fontSize: 24, color: colors.foreground),
                ),
                const SizedBox(height: 6),
                KineticText(
                  'App information, privacy, and support.',
                  muted: true,
                  style: AppTheme.bodyStyle(colors).copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 24),
          sliver: SliverList.list(
            children: [
              _AboutSection(
                label: 'App version',
                child: FutureBuilder<AppVersionInfo>(
                  future: _version,
                  builder: (context, snapshot) {
                    final version = snapshot.data;
                    final versionText = version == null
                        ? snapshot.hasError
                              ? 'Unavailable'
                              : 'Loading…'
                        : version.version;
                    return LedgerFrame(
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: colors.accent.withValues(alpha: 0.16),
                              borderRadius: AppTheme.radius,
                            ),
                            child: Icon(
                              Icons.info_outline_rounded,
                              color: colors.accent,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                KineticText(
                                  versionText,
                                  key: const Key('about_version'),
                                  style: AppTheme.titleStyle(
                                    colors,
                                  ).copyWith(fontSize: 20),
                                ),
                                if (version != null) ...[
                                  const SizedBox(height: 3),
                                  KineticText(
                                    'Build ${version.buildNumber}',
                                    key: const Key('about_build_number'),
                                    muted: true,
                                    style: AppTheme.bodyStyle(
                                      colors,
                                    ).copyWith(fontSize: 13),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
              const _AboutSection(
                label: 'Privacy',
                child: LedgerFrame(
                  child: _InformationBlock(
                    icon: Icons.shield_outlined,
                    title: 'Your data stays yours',
                    detail:
                        'Your holdings, Zakat settings, and preferences are stored locally on this device. MONIZ only contacts public market-data services to refresh gold and silver prices; your holding details are not included in those requests.',
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const _AboutSection(
                label: 'Widgets',
                child: LedgerFrame(
                  child: _InformationBlock(
                    icon: Icons.widgets_outlined,
                    title: 'Android home-screen widget',
                    detail:
                        'Add the MONIZ widget from your Android home-screen widget picker for a quick launcher tile that shows the installed app version.',
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _AboutSection(
                label: 'Support',
                child: LedgerFrame(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _InformationBlock(
                        icon: Icons.support_agent_rounded,
                        title: 'Need a hand?',
                        detail:
                            'Report a problem or request a feature through the MONIZ support page. Include your app version and Android model so the issue is easier to reproduce.',
                      ),
                      const SizedBox(height: 14),
                      SelectableText(
                        _supportUrl,
                        style: AppTheme.bodyStyle(colors).copyWith(
                          color: colors.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      BrutalistButton(
                        label: 'Copy support link',
                        expand: true,
                        tone: BrutalistButtonTone.primary,
                        onPressed: _copySupportLink,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _copySupportLink() async {
    await Clipboard.setData(const ClipboardData(text: _supportUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Support link copied')));
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KineticText(
          label,
          uppercase: true,
          style: AppTheme.labelStyle(
            colors,
          ).copyWith(color: colors.accent, fontSize: 13),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _InformationBlock extends StatelessWidget {
  const _InformationBlock({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colors.accent, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KineticText(
                title,
                style: AppTheme.titleStyle(colors).copyWith(fontSize: 18),
              ),
              const SizedBox(height: 5),
              KineticText(
                detail,
                muted: true,
                style: AppTheme.bodyStyle(
                  colors,
                ).copyWith(fontSize: 13, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
