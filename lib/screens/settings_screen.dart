import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/zephyr_api.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../theme/colors.dart';
import '../theme/zephyr_theme.dart';
import '../widgets/toast.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _serverController = TextEditingController();
  bool _autoSelectHighConfidence = true;

  @override
  void initState() {
    super.initState();
    _serverController.text = ZephyrApi().baseUrl;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoSelectHighConfidence = prefs.getBool('auto_select_high_confidence') ?? true;
    });
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final authNotifier = ref.read(authProvider.notifier);
    final libraryState = ref.watch(libraryProvider);
    final downloadedCount = libraryState.downloadedTracks.length;
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 40,
          vertical: isMobile ? 16 : 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settings',
              style: TextStyle(fontSize: isMobile ? 26 : 32, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: isMobile ? 20 : 32),

            // Server configuration section
            _buildSection(
              title: 'Server Settings',
              isMobile: isMobile,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Zephyr Server Address',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _serverController.text.trim() == 'https://zephyrmusic.duckdns.org'
                                ? ZephyrColors.primary.withValues(alpha: 0.15)
                                : Colors.transparent,
                            side: BorderSide(
                              color: _serverController.text.trim() == 'https://zephyrmusic.duckdns.org'
                                  ? ZephyrColors.primary
                                  : ZephyrColors.bgLight,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: Icon(
                            Icons.cloud_rounded,
                            size: 16,
                            color: _serverController.text.trim() == 'https://zephyrmusic.duckdns.org'
                                ? ZephyrColors.primary
                                : ZephyrColors.textDim,
                          ),
                          label: Text(
                            'Cloud (Default)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _serverController.text.trim() == 'https://zephyrmusic.duckdns.org'
                                  ? ZephyrColors.primary
                                  : ZephyrColors.text,
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              _serverController.text = 'https://zephyrmusic.duckdns.org';
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _serverController.text.trim() == 'http://localhost:8000'
                                ? ZephyrColors.primary.withValues(alpha: 0.15)
                                : Colors.transparent,
                            side: BorderSide(
                              color: _serverController.text.trim() == 'http://localhost:8000'
                                  ? ZephyrColors.primary
                                  : ZephyrColors.bgLight,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: Icon(
                            Icons.computer_rounded,
                            size: 16,
                            color: _serverController.text.trim() == 'http://localhost:8000'
                                ? ZephyrColors.primary
                                : ZephyrColors.textDim,
                          ),
                          label: Text(
                            'Localhost',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _serverController.text.trim() == 'http://localhost:8000'
                                  ? ZephyrColors.primary
                                  : ZephyrColors.text,
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              _serverController.text = 'http://localhost:8000';
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isMobile) ...[
                    TextField(
                      controller: _serverController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        fillColor: ZephyrColors.bgDark,
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: ZephyrColors.bgLight.withValues(alpha: 0.4)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: ZephyrColors.primary),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: const Text('Save'),
                      style: ZephyrTheme.primaryPillStyle(),
                      onPressed: () async {
                        final newUrl = _serverController.text.trim();
                        if (newUrl.isNotEmpty) {
                          await authNotifier.updateServerUrl(newUrl);
                          if (context.mounted) {
                            ZephyrToast.show(context, 'Server URL updated!');
                          }
                        }
                      },
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _serverController,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              fillColor: ZephyrColors.bgDark,
                              filled: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: ZephyrColors.bgLight.withValues(alpha: 0.4)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: ZephyrColors.primary),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.save_rounded, size: 16),
                          label: const Text('Save'),
                          style: ZephyrTheme.primaryPillStyle(),
                          onPressed: () async {
                            final newUrl = _serverController.text.trim();
                            if (newUrl.isNotEmpty) {
                              await authNotifier.updateServerUrl(newUrl);
                              if (context.mounted) {
                                ZephyrToast.show(context, 'Server URL updated!');
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Storage & Downloads Manager Section
            _buildSection(
              title: 'Storage & Downloads Manager',
              isMobile: isMobile,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isMobile) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Downloaded Tracks',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$downloadedCount tracks saved for offline listening',
                          style: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.sync_rounded, size: 16, color: ZephyrColors.primary),
                          label: const Text('Resync Library', style: TextStyle(color: ZephyrColors.primary, fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: ZephyrColors.primary.withValues(alpha: 0.5)),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          onPressed: () {
                            ref.read(libraryProvider.notifier).loadLibrary();
                            ZephyrToast.show(context, 'Library resynchronized!');
                          },
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Downloaded Tracks',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$downloadedCount tracks saved for offline listening',
                                style: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.sync_rounded, size: 16, color: ZephyrColors.primary),
                          label: const Text('Resync Library', style: TextStyle(color: ZephyrColors.primary, fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: ZephyrColors.primary.withValues(alpha: 0.5)),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          onPressed: () {
                            ref.read(libraryProvider.notifier).loadLibrary();
                            ZephyrToast.show(context, 'Library resynchronized!');
                          },
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Audio Quality',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: ZephyrColors.textDim),
                  ),
                  const SizedBox(height: 8),
                  _buildQualityPill('High Quality 320 kbps MP3', isActive: true),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Resolution & Track Matching section
            _buildSection(
              title: 'Resolution & Track Matching',
              isMobile: isMobile,
              child: Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-Select High Confidence Matches', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  subtitle: const Text(
                    'Automatically confirm candidate matches with ≥ 85% match score without opening the candidate selection modal (Audio tracks only).',
                    style: TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                  ),
                  value: _autoSelectHighConfidence,
                  activeThumbColor: ZephyrColors.primary,
                  onChanged: (val) async {
                    setState(() => _autoSelectHighConfidence = val);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('auto_select_high_confidence', val);
                    if (context.mounted) {
                      ZephyrToast.show(
                        context,
                        val ? 'Auto-select high confidence matches enabled' : 'Auto-select disabled (all matches require manual selection)',
                      );
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Profile info section
            _buildSection(
              title: 'Profile',
              isMobile: isMobile,
              child: isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Logged in as ${authState.username ?? 'Unknown'}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          authState.isAdmin ? 'Role: Administrator' : 'Role: Standard User',
                          style: const TextStyle(color: ZephyrColors.textDim, fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.logout_rounded, size: 16),
                          label: const Text('Sign Out'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ZephyrColors.error,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ),
                          onPressed: () {
                            authNotifier.logout();
                          },
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Logged in as ${authState.username ?? 'Unknown'}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                authState.isAdmin ? 'Role: Administrator' : 'Role: Standard User',
                                style: const TextStyle(color: ZephyrColors.textDim, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.logout_rounded, size: 16),
                          label: const Text('Sign Out'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ZephyrColors.error,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ),
                          onPressed: () {
                            authNotifier.logout();
                          },
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),

            // About section
            _buildSection(
              title: 'About Zephyr',
              isMobile: isMobile,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Zephyr Music Client v1.0.8 Nightly',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Zephyr is a self-hosted audio streaming application that acts as a client for custom Spotify replacement backends. It integrates YouTube Music matching, synced lyrics (.lrc parser), playlist management, and listening history databases.',
                    style: TextStyle(color: ZephyrColors.textDim, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityPill(String label, {required bool isActive}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? ZephyrColors.primary.withValues(alpha: 0.15) : ZephyrColors.bgDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? ZephyrColors.primary : ZephyrColors.bgLight.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          color: isActive ? ZephyrColors.primary : ZephyrColors.textDim,
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child, required bool isMobile}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: ZephyrColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ZephyrColors.bgLight.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: ZephyrColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
