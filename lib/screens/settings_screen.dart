import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/zephyr_api.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../theme/colors.dart';
import '../theme/zephyr_theme.dart';
import '../utils/app_logger.dart';
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

            // Diagnostics & Debug Logs section
            _buildSection(
              title: 'Diagnostics & Debug Logs',
              isMobile: isMobile,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Client runtime logs track playback, queue transitions, auth token refreshes, and app lifecycle events with timestamps.',
                    style: TextStyle(color: ZephyrColors.textDim, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.visibility_outlined, size: 16),
                        label: const Text('View Logs'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ZephyrColors.bgLight,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _showLogsDialog(context),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy to Clipboard'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ZephyrColors.primary.withValues(alpha: 0.2),
                          foregroundColor: ZephyrColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          final logsText = AppLogger.instance.getLogsAsString();
                          Clipboard.setData(ClipboardData(text: logsText));
                          ZephyrToast.show(context, 'Copied ${AppLogger.instance.getLogs().length} log entries');
                        },
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Export log.txt'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ZephyrColors.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _exportLogFile(context),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        label: const Text('Clear Logs'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ZephyrColors.error,
                          side: const BorderSide(color: ZephyrColors.error),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          await AppLogger.instance.clearLogs();
                          if (context.mounted) {
                            ZephyrToast.show(context, 'Debug logs cleared');
                          }
                        },
                      ),
                    ],
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
                    'Zephyr Music Client v1.0.9 Nightly',
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

  void _showLogsDialog(BuildContext context) {
    final logs = AppLogger.instance.getLogs();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: ZephyrColors.bgDark,
            title: Row(
              children: [
                const Icon(Icons.receipt_long_rounded, color: ZephyrColors.primary, size: 20),
                const SizedBox(width: 8),
                const Text('Runtime Logs', style: TextStyle(color: Colors.white, fontSize: 16)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18, color: ZephyrColors.textDim),
                  tooltip: 'Copy all to clipboard',
                  onPressed: () {
                    final text = AppLogger.instance.getLogsAsString();
                    Clipboard.setData(ClipboardData(text: text));
                    ZephyrToast.show(context, 'Copied ${logs.length} log lines to clipboard');
                  },
                ),
              ],
            ),
            content: SizedBox(
              width: 600,
              height: 400,
              child: logs.isEmpty
                  ? const Center(child: Text('No logs recorded yet.', style: TextStyle(color: ZephyrColors.textDim)))
                  : Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: ZephyrColors.bgCard,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: logs.length,
                        reverse: true,
                        itemBuilder: (context, index) {
                          final log = logs[logs.length - 1 - index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Text(
                              log,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close', style: TextStyle(color: ZephyrColors.primary)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportLogFile(BuildContext context) async {
    try {
      final text = AppLogger.instance.getLogsAsString();
      if (text.isEmpty) {
        if (context.mounted) ZephyrToast.show(context, 'No logs to export');
        return;
      }

      Directory? exportDir;
      if (Platform.isAndroid) {
        exportDir = Directory('/storage/emulated/0/Download');
        if (!exportDir.existsSync()) {
          exportDir = await getExternalStorageDirectory();
        }
      } else if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        exportDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      } else {
        exportDir = await getApplicationDocumentsDirectory();
      }

      if (exportDir != null) {
        final targetFile = File('${exportDir.path}/zephyr_log_${DateTime.now().millisecondsSinceEpoch}.txt');
        await targetFile.writeAsString(text);
        if (context.mounted) {
          ZephyrToast.show(context, 'Exported logs to ${targetFile.path}');
        }
      } else {
        final file = await AppLogger.instance.getLogFile();
        if (file != null && context.mounted) {
          ZephyrToast.show(context, 'Log file saved at: ${file.path}');
        }
      }
    } catch (e) {
      if (context.mounted) {
        ZephyrToast.show(context, 'Export failed: $e', isError: true);
      }
    }
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
