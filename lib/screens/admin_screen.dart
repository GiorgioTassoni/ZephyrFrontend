import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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
  Map<String, dynamic>? _cookiesState;
  bool _isLoading = true;
  bool _isRetryingDownloads = false;
  bool _isUploadingCookies = false;
  String? _cookiesUploadError;
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
      Map<String, dynamic>? cookiesMap;

      try {
        statsMap = await _api.getAdminStats();
      } catch (_) {}

      try {
        orphansMap = await _api.getOrphans();
      } catch (_) {}

      try {
        final cRes = await _api.getYoutubeCookies();
        if (cRes.containsKey('cookies') && cRes['cookies'] is Map) {
          cookiesMap = Map<String, dynamic>.from(cRes['cookies'] as Map);
        } else {
          cookiesMap = cRes;
        }
      } catch (_) {}

      setState(() {
        _users = usersList;
        _pendingUsers = pendingList;
        _stats = statsMap;
        _orphans = orphansMap;
        _cookiesState = cookiesMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAndUploadCookies() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      List<int>? bytes = file.bytes;
      if (bytes == null && file.path != null && !kIsWeb) {
        bytes = await File(file.path!).readAsBytes();
      }

      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read the selected cookies file.'),
            backgroundColor: ZephyrColors.error,
          ),
        );
        return;
      }

      if (bytes.length > 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File too large (maximum 1 MB allowed).'),
            backgroundColor: ZephyrColors.error,
          ),
        );
        return;
      }

      setState(() {
        _isUploadingCookies = true;
        _cookiesUploadError = null;
      });

      final response = await _api.uploadYoutubeCookies(bytes, file.name);

      if (!mounted) return;
      setState(() {
        if (response.containsKey('cookies') && response['cookies'] is Map) {
          _cookiesState = Map<String, dynamic>.from(response['cookies'] as Map);
        }
        _isUploadingCookies = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['message']?.toString() ?? 'YouTube cookies updated — effective immediately!'),
          backgroundColor: ZephyrColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final cleanMsg = e.toString().replaceAll('Exception: ', '');
      setState(() {
        _isUploadingCookies = false;
        _cookiesUploadError = cleanMsg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update cookies: $cleanMsg'),
          backgroundColor: ZephyrColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _approveUser(String username) async {
    try {
      await _api.approveUser(username);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Approved user "$username" successfully.'),
          backgroundColor: ZephyrColors.success,
        ),
      );
      _fetchAdminData(); // Refresh lists
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to approve: $e'), backgroundColor: ZephyrColors.error),
      );
    }
  }

  Future<void> _promoteToCurator(String username) async {
    try {
      await _api.promoteToCurator(username);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User "$username" promoted to Curator successfully.'),
          backgroundColor: ZephyrColors.success,
        ),
      );
      _fetchAdminData(); // Refresh lists
    } catch (e) {
      if (!mounted) return;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Re-queued $count failed tracks successfully.'),
          backgroundColor: ZephyrColors.success,
        ),
      );
      _fetchAdminData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to retry downloads: $e'), backgroundColor: ZephyrColors.error),
      );
    } finally {
      if (mounted) setState(() {
        _isRetryingDownloads = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    if (isMobile) {
      return Scaffold(
        backgroundColor: ZephyrColors.bgDark,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: ZephyrColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: ZephyrColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(
                    Icons.desktop_windows_rounded,
                    size: 64,
                    color: ZephyrColors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Only available on desktop',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: ZephyrColors.text,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'The Admin Panel contains advanced system management tools designed for desktop screens. Please access Zephyr from your computer to use these tools.',
                  style: TextStyle(
                    fontSize: 14,
                    color: ZephyrColors.textDim,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

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

            // YouTube Cookies / Download Stack Section
            _buildYoutubeCookiesSection(),
            const SizedBox(height: 24),

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

  Widget _buildYoutubeCookiesSection() {
    final cookies = _cookiesState ?? {};
    final bool exists = cookies['exists'] == true;
    final int sizeBytes = (cookies['size_bytes'] as num?)?.toInt() ?? 0;
    final String path = cookies['path']?.toString() ?? '/app/youtube_cookies.txt';
    final String? modifiedAt = cookies['modified_at']?.toString();
    final List present = cookies['present'] is List ? cookies['present'] : [];
    final List missing = cookies['missing'] is List ? cookies['missing'] : [];

    final bool isHealthy = exists && missing.isEmpty;
    final bool isWarning = exists && missing.isNotEmpty;

    final Color statusColor = isHealthy
        ? ZephyrColors.success
        : (isWarning ? ZephyrColors.warning : ZephyrColors.error);
    final String statusText = isHealthy
        ? 'Healthy (Auth Cookies Active)'
        : (isWarning ? 'Warning: Missing Required Auth Cookies' : 'Cookie File Missing');
    final IconData statusIcon = isHealthy
        ? Icons.check_circle
        : (isWarning ? Icons.warning_amber_rounded : Icons.error_outline);

    final double sizeKb = sizeBytes / 1024.0;

    return _buildAdminSection(
      title: 'YouTube / Download Stack (Cookies)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Authentication cookies (Netscape cookies.txt) used by the background download worker to fetch audio streams from YouTube and prevent HTTP 403 Forbidden errors. Changes take effect immediately.',
            style: TextStyle(color: ZephyrColors.textDim, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),

          if (_cookiesUploadError != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ZephyrColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ZephyrColors.error.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error, color: ZephyrColors.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _cookiesUploadError!,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tip: Export cookies from an active logged-in youtube.com browser session in Netscape format.',
                          style: TextStyle(color: ZephyrColors.textDim, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: ZephyrColors.textDim),
                    onPressed: () => setState(() => _cookiesUploadError = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Status & Details Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ZephyrColors.bgLight.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(statusIcon, color: statusColor, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (exists)
                            Text(
                              'Path: $path • ${sizeKb.toStringAsFixed(1)} KB${modifiedAt != null && modifiedAt.isNotEmpty ? " • Modified: $modifiedAt" : ""}',
                              style: const TextStyle(color: ZephyrColors.textDim, fontSize: 12),
                            )
                          else
                            const Text(
                              'No cookie file located at /app/youtube_cookies.txt on server',
                              style: TextStyle(color: ZephyrColors.textDim, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ZephyrColors.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      icon: _isUploadingCookies
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file, size: 18),
                      label: Text(_isUploadingCookies ? 'Uploading...' : 'Upload cookies.txt'),
                      onPressed: _isUploadingCookies ? null : _pickAndUploadCookies,
                    ),
                  ],
                ),
                if (present.isNotEmpty || missing.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Divider(color: ZephyrColors.bgLight, height: 1),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Required Auth Cookies:', style: TextStyle(fontSize: 12, color: ZephyrColors.textMuted)),
                      ...present.map((c) => Chip(
                            avatar: const Icon(Icons.check, size: 14, color: ZephyrColors.success),
                            label: Text(c.toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ZephyrColors.success)),
                            backgroundColor: ZephyrColors.success.withValues(alpha: 0.15),
                            side: BorderSide(color: ZephyrColors.success.withValues(alpha: 0.3)),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                          )),
                      ...missing.map((c) => Chip(
                            avatar: const Icon(Icons.close, size: 14, color: ZephyrColors.error),
                            label: Text(c.toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ZephyrColors.error)),
                            backgroundColor: ZephyrColors.error.withValues(alpha: 0.15),
                            side: BorderSide(color: ZephyrColors.error.withValues(alpha: 0.3)),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                          )),
                    ],
                  ),
                ],
              ],
            ),
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
