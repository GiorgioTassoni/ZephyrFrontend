import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../providers/auth_provider.dart';
import '../theme/colors.dart';
import '../widgets/toast.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _serverController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _serverController.text = ZephyrApi().baseUrl;
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

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Settings',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),

            // Server configuration section
            _buildSection(
              title: 'Server Settings',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Zephyr Server Address',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _serverController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: ZephyrColors.bgLight),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: ZephyrColors.primary),
                            ),
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ZephyrColors.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        ),
                        onPressed: () async {
                          final newUrl = _serverController.text.trim();
                          if (newUrl.isNotEmpty) {
                            await authNotifier.updateServerUrl(newUrl);
                            if (context.mounted) {
                              ZephyrToast.show(context, 'Server URL updated!');
                            }
                          }
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Profile info section
            _buildSection(
              title: 'Profile',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Logged in as ${authState.username ?? 'Unknown'}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        authState.isAdmin ? 'Role: Administrator' : 'Role: Standard User',
                        style: const TextStyle(color: ZephyrColors.textDim, fontSize: 14),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZephyrColors.error,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      authNotifier.logout();
                    },
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // About section
            _buildSection(
              title: 'About Zephyr',
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Zephyr Music Client v1.0.0',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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

  Widget _buildSection({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ZephyrColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ZephyrColors.bgLight.withOpacity(0.5)),
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
