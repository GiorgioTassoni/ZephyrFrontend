import 'package:flutter/material.dart';
import '../api/zephyr_api.dart';
import '../theme/colors.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _api = ZephyrApi();
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _pendingUsers = [];
  Map<String, dynamic> _stats = {};
  Map<String, dynamic> _orphans = {};
  bool _isLoading = true;
  bool _isRetryingDownloads = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAdminData();
  }

  Future<void> _fetchAdminData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final usersList = await _api.getUsers();
      final pendingList = await _api.getPendingUsers();
      Map<String, dynamic> statsMap = {};
      Map<String, dynamic> orphansMap = {};

      try {
        statsMap = await _api.getAdminStats();
        orphansMap = await _api.getOrphans();
      } catch (_) {
        // Fallback silently if stats/orphans endpoint fails or is partially implemented
      }

      setState(() {
        _users = usersList;
        _pendingUsers = pendingList;
        _stats = statsMap;
        _orphans = orphansMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _approveUser(String username) async {
    try {
      await _api.approveUser(username);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Approved user "$username" successfully.'),
          backgroundColor: ZephyrColors.success,
        ),
      );
      _fetchAdminData(); // Refresh lists
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to approve: $e'), backgroundColor: ZephyrColors.error),
      );
    }
  }

  Future<void> _promoteToCurator(String username) async {
    try {
      await _api.promoteToCurator(username);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User "$username" promoted to Curator successfully.'),
          backgroundColor: ZephyrColors.success,
        ),
      );
      _fetchAdminData(); // Refresh lists
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to promote: $e'), backgroundColor: ZephyrColors.error),
      );
    }
  }

  Future<void> _retryFailedDownloads() async {
    setState(() {
      _isRetryingDownloads = true;
    });
    try {
      final count = await _api.retryFailedDownloads();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Re-queued $count failed tracks successfully.'),
          backgroundColor: ZephyrColors.success,
        ),
      );
      _fetchAdminData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to retry downloads: $e'), backgroundColor: ZephyrColors.error),
      );
    } finally {
      setState(() {
        _isRetryingDownloads = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: ZephyrColors.primary));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Admin Error: $_error', style: const TextStyle(color: ZephyrColors.error)),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ZephyrColors.primary),
              onPressed: _fetchAdminData,
              child: const Text('Retry', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Admin Dashboard',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // System Statistics Section
            if (_stats.isNotEmpty) ...[
              _buildStatsSection(),
              const SizedBox(height: 24),
            ],

            // Pending User Approvals Card
            _buildAdminSection(
              title: 'Pending Registration Approvals (${_pendingUsers.length})',
              child: _pendingUsers.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Text(
                        'No registrations waiting for approval.',
                        style: TextStyle(color: ZephyrColors.textDim, fontStyle: FontStyle.italic),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _pendingUsers.length,
                      separatorBuilder: (context, index) => const Divider(color: ZephyrColors.bgLight, height: 1),
                      itemBuilder: (context, index) {
                        final user = _pendingUsers[index];
                        final username = user['username'] ?? '';
                        return Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(
                              backgroundColor: ZephyrColors.bgLight,
                              child: Icon(Icons.person_add_disabled, color: ZephyrColors.warning),
                            ),
                            title: Text(username, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: const Text('Awaiting approval'),
                            trailing: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: ZephyrColors.primary,
                                foregroundColor: Colors.black,
                              ),
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Approve'),
                              onPressed: () => _approveUser(username),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 24),

            // Active Users List Card
            _buildAdminSection(
              title: 'All Registered Users (${_users.length})',
              child: _users.isEmpty
                  ? const Text('No users in database.')
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _users.length,
                      separatorBuilder: (context, index) => const Divider(color: ZephyrColors.bgLight, height: 1),
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        final username = user['username'] ?? '';
                        final role = user['role'] ?? (user['is_admin'] == true ? 'admin' : 'user');
                        final isApproved = user['is_approved'] ?? false;

                        return Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: ZephyrColors.bgLight,
                              child: Icon(
                                Icons.person,
                                color: role == 'admin'
                                    ? ZephyrColors.primary
                                    : (role == 'curator' ? const Color(0xFF9C27B0) : ZephyrColors.textDim),
                              ),
                            ),
                            title: Text(username, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Row(
                              children: [
                                Text(role == 'admin'
                                    ? 'Administrator'
                                    : (role == 'curator' ? 'Curator' : 'Standard User')),
                                const SizedBox(width: 8),
                                const Icon(Icons.circle, size: 4, color: ZephyrColors.textDim),
                                const SizedBox(width: 8),
                                Text(isApproved ? 'Approved' : 'Awaiting Approval'),
                              ],
                            ),
                            trailing: isApproved
                                ? (role == 'user'
                                    ? IconButton(
                                        icon: const Icon(Icons.badge, color: ZephyrColors.primary),
                                        tooltip: 'Promote to Curator',
                                        onPressed: () => _promoteToCurator(username),
                                      )
                                    : null)
                                : ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: ZephyrColors.primary,
                                      foregroundColor: Colors.black,
                                    ),
                                    icon: const Icon(Icons.check, size: 16),
                                    label: const Text('Approve'),
                                    onPressed: () => _approveUser(username),
                                  ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 24),

            // Orphan Files scanning
            if (_orphans.isNotEmpty) ...[
              _buildOrphansSection(),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    final tracks = _stats['tracks'] ?? {};
    final disk = _stats['disk'] ?? {};

    final totalTracks = tracks['total'] ?? 0;
    final completedTracks = tracks['completed'] ?? 0;
    final pendingTracks = tracks['pending'] ?? 0;
    final failedTracks = tracks['failed'] ?? 0;

    final tracksSize = disk['tracks_size_mb'] ?? 0.0;
    final thumbnailsSize = disk['thumbnails_size_mb'] ?? 0.0;

    return _buildAdminSection(
      title: 'Library Statistics & Disk Usage',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMetricTile('Total Tracks', '$totalTracks', Icons.music_note),
              ),
              Expanded(
                child: _buildMetricTile('Completed', '$completedTracks', Icons.check_circle_outline, color: ZephyrColors.success),
              ),
              Expanded(
                child: _buildMetricTile('Pending', '$pendingTracks', Icons.hourglass_empty, color: ZephyrColors.warning),
              ),
              Expanded(
                child: _buildMetricTile('Failed', '$failedTracks', Icons.error_outline, color: ZephyrColors.error),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: ZephyrColors.bgLight),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Audio Tracks size on VPS: ${tracksSize.toStringAsFixed(1)} MB', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Cached covers size: ${thumbnailsSize.toStringAsFixed(1)} MB', style: const TextStyle(color: ZephyrColors.textDim)),
                ],
              ),
              if (failedTracks > 0)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZephyrColors.error,
                    foregroundColor: Colors.white,
                  ),
                  icon: _isRetryingDownloads
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry Failed Downloads'),
                  onPressed: _isRetryingDownloads ? null : _retryFailedDownloads,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrphansSection() {
    final List missingFiles = _orphans['records_without_file'] ?? [];
    final List strayFiles = _orphans['files_without_record'] ?? [];

    if (missingFiles.isEmpty && strayFiles.isEmpty) {
      return _buildAdminSection(
        title: 'Orphan File Scanner',
        child: const Text(
          'No catalog inconsistencies found. physical files and DB match perfectly.',
          style: TextStyle(color: ZephyrColors.success, fontStyle: FontStyle.italic),
        ),
      );
    }

    return _buildAdminSection(
      title: 'Catalog Inconsistencies (Orphan Scanner)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (missingFiles.isNotEmpty) ...[
            Text('DB Records Missing Physical Audio Files (${missingFiles.length}):', style: const TextStyle(fontWeight: FontWeight.bold, color: ZephyrColors.warning)),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: missingFiles.length,
              itemBuilder: (context, index) {
                final track = missingFiles[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(
                    '• [${track['id']}] ${track['title']} (Expected: ${track['local_path']})',
                    style: const TextStyle(fontSize: 12, color: ZephyrColors.textDim),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
          if (strayFiles.isNotEmpty) ...[
            Text('Unlinked Stray Audio Files on Disk (${strayFiles.length}):', style: const TextStyle(fontWeight: FontWeight.bold, color: ZephyrColors.warning)),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: strayFiles.length,
              itemBuilder: (context, index) {
                final file = strayFiles[index];
                final sizeMb = (file['size_kb'] ?? 0.0) / 1024.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(
                    '• ${file['file']} (${sizeMb.toStringAsFixed(1)} MB)',
                    style: const TextStyle(fontSize: 12, color: ZephyrColors.textDim),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, {Color color = Colors.white}) {
    return Container(
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: ZephyrColors.bgLight.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: ZephyrColors.textMuted)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdminSection({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ZephyrColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ZephyrColors.bgLight.withValues(alpha: 0.5)),
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
