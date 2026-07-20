import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../theme/colors.dart';
import '../widgets/cover_image.dart';
import '../providers/library_provider.dart';

class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

enum StatsTab { overview, topTracks, topArtists }

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  final _api = ZephyrApi();
  String _selectedPeriod = 'all'; // '1m' | '6m' | '1y' | 'all'
  StatsTab _activeTab = StatsTab.overview;
  bool _isLoading = true;
  String? _error;

  int _totalListens = 0;
  int _uniqueTracks = 0;
  int _totalListenSeconds = 0;
  List<Map<String, dynamic>> _topTracks = [];
  List<Map<String, dynamic>> _topArtists = [];
  List<Map<String, dynamic>> _dailyActivity = [];

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await _api.getHistoryStatistics(_selectedPeriod);
      final stats = res['statistics'] ?? {};
      final List rawTracks = stats['top_tracks'] ?? [];
      final List rawArtists = stats['top_artists'] ?? [];
      final List rawActivity = stats['daily_activity'] ?? [];

      setState(() {
        _totalListens = stats['total_listens'] ?? 0;
        _uniqueTracks = stats['unique_tracks'] ?? 0;
        _totalListenSeconds = stats['total_listen_seconds'] ?? 0;
        _topTracks = rawTracks.map((e) => Map<String, dynamic>.from(e)).toList();
        _topArtists = rawArtists.map((e) => Map<String, dynamic>.from(e)).toList();
        _dailyActivity = rawActivity.map((e) => Map<String, dynamic>.from(e)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onPeriodChanged(String period) {
    if (_selectedPeriod == period) return;
    setState(() {
      _selectedPeriod = period;
    });
    _fetchStats();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(libraryProvider.select((s) => s.history), (prev, next) {
      _fetchStats();
    });

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: ZephyrColors.primary))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error loading statistics: $_error', style: const TextStyle(color: ZephyrColors.error)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: ZephyrColors.primary),
                        onPressed: _fetchStats,
                        child: const Text('Retry', style: TextStyle(color: Colors.black)),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Listening Insights',
                                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Analyze your personal musical habits and metrics',
                                style: TextStyle(color: ZephyrColors.textDim, fontSize: 14),
                              ),
                            ],
                          ),
                          _buildPeriodSelector(),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildTabSelector(),
                      const SizedBox(height: 32),

                      // Conditional Tab View
                      if (_activeTab == StatsTab.overview) ...[
                        // KPI Cards
                        Row(
                          children: [
                            Expanded(
                              child: _buildKPICard(
                                title: 'TOTAL LISTENS',
                                value: '$_totalListens',
                                icon: Icons.play_circle_outline,
                                color: ZephyrColors.primary,
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: _buildKPICard(
                                title: 'UNIQUE TRACKS',
                                value: '$_uniqueTracks',
                                icon: Icons.music_note_outlined,
                                color: const Color(0xFF9C27B0),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: _buildKPICard(
                                title: 'LISTEN TIME',
                                value: _formatListenTime(_totalListenSeconds),
                                icon: Icons.access_time_outlined,
                                color: const Color(0xFF1DB954),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),

                        // Daily Activity Chart
                        if (_dailyActivity.isNotEmpty) ...[
                          _buildSectionHeader('Listening Frequency'),
                          const SizedBox(height: 16),
                          _buildDailyActivityChart(),
                        ],
                      ] else if (_activeTab == StatsTab.topTracks) ...[
                        _buildTopTracksGrid(),
                      ] else if (_activeTab == StatsTab.topArtists) ...[
                        _buildTopArtistsList(),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildTabSelector() {
    final tabs = {
      StatsTab.overview: 'Overview',
      StatsTab.topTracks: 'Top Tracks',
      StatsTab.topArtists: 'Top Artists',
    };

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ZephyrColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ZephyrColors.bgLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: tabs.entries.map((entry) {
          final isSelected = _activeTab == entry.key;
          return GestureDetector(
            onTap: () => setState(() => _activeTab = entry.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? ZephyrColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  color: isSelected ? Colors.black : ZephyrColors.textDim,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    final periods = {
      '1m': '30 Days',
      '6m': '6 Months',
      '1y': '1 Year',
      'all': 'All Time',
    };

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ZephyrColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ZephyrColors.bgLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: periods.entries.map((entry) {
          final isSelected = _selectedPeriod == entry.key;
          return GestureDetector(
            onTap: () => _onPeriodChanged(entry.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? ZephyrColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  color: isSelected ? Colors.black : ZephyrColors.textDim,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _formatListenTime(int seconds) {
    if (seconds <= 0) return '0m';
    final minutes = seconds ~/ 60;
    if (minutes < 60) {
      return '${minutes}m';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${remainingMinutes}m';
  }

  Widget _buildKPICard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ZephyrColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ZephyrColors.bgLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: ZephyrColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Icon(
            icon,
            size: 48,
            color: color.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildDailyActivityChart() {
    // Find the maximum listen count to scale the bars
    final maxListens = _dailyActivity.map((e) => (e['listen_count'] as num).toInt()).fold(1, math.max);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ZephyrColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ZephyrColors.bgLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Daily Activity',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: ZephyrColors.textDim),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 150,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _dailyActivity.length,
              itemBuilder: (context, index) {
                final item = _dailyActivity[index];
                final dateStr = item['day'] ?? '';
                final count = (item['listen_count'] as num).toInt();
                final heightFactor = count / maxListens;

                // Format date string (YYYY-MM-DD -> MM/DD)
                String shortDate = dateStr;
                if (dateStr.length >= 10) {
                  final parts = dateStr.split('-');
                  if (parts.length >= 3) {
                    shortDate = '${parts[1]}/${parts[2]}';
                  }
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Tooltip value
                      Text(
                        count > 0 ? '$count' : '',
                        style: const TextStyle(fontSize: 10, color: ZephyrColors.primary),
                      ),
                      const SizedBox(height: 6),
                      // Colored bar
                      Container(
                        width: 24,
                        height: 90 * heightFactor,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              ZephyrColors.primary.withValues(alpha: 0.3),
                              ZephyrColors.primary,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Date label
                      Text(
                        shortDate,
                        style: const TextStyle(fontSize: 9, color: ZephyrColors.textMuted),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTracksGrid() {
    if (_topTracks.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: ZephyrColors.bgCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text('No tracks played in this period.', style: TextStyle(color: ZephyrColors.textDim)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 2;
        if (constraints.maxWidth >= 1200) {
          crossAxisCount = 7;
        } else if (constraints.maxWidth >= 1000) {
          crossAxisCount = 6;
        } else if (constraints.maxWidth >= 800) {
          crossAxisCount = 5;
        } else if (constraints.maxWidth >= 600) {
          crossAxisCount = 4;
        } else if (constraints.maxWidth >= 450) {
          crossAxisCount = 3;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _topTracks.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.70,
          ),
          itemBuilder: (context, index) {
            final item = _topTracks[index];
            final title = item['title'] ?? 'Unknown Track';
            final artistsList = item['artists'];
            final artistsStr = artistsList is List ? artistsList.join(', ') : (artistsList ?? 'Unknown Artist').toString();
            final listens = item['listen_count'] ?? 0;
            final videoId = item['id'] ?? '';
            final durationSec = item['duration'] ?? 0;
            final totalDurationSec = durationSec * listens;

            return Container(
              decoration: BoxDecoration(
                color: ZephyrColors.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ZephyrColors.bgLight.withValues(alpha: 0.5)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Square cover image
                      AspectRatio(
                        aspectRatio: 1.0,
                        child: CoverImage(
                          videoId: videoId,
                          borderRadius: 0,
                        ),
                      ),
                      // Text content
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      color: ZephyrColors.text,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    artistsStr,
                                    style: const TextStyle(
                                      color: ZephyrColors.textDim,
                                      fontSize: 10,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                              Text(
                                '$listens plays • ${_formatListenTime(totalDurationSec)}',
                                style: const TextStyle(
                                  color: ZephyrColors.textMuted,
                                  fontSize: 9,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Rank badge in top-left
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '#${index + 1}',
                        style: const TextStyle(
                          color: ZephyrColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTopArtistsList() {
    if (_topArtists.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: ZephyrColors.bgCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text('No artists played in this period.', style: TextStyle(color: ZephyrColors.textDim)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: ZephyrColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ZephyrColors.bgLight.withValues(alpha: 0.5)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _topArtists.length,
        separatorBuilder: (context, index) => const Divider(color: ZephyrColors.bgLight, height: 1),
        itemBuilder: (context, index) {
          final item = _topArtists[index];
          final name = item['name'] ?? 'Unknown Artist';
          final listens = item['listen_count'] ?? 0;

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: SizedBox(
              width: 28,
              child: Text(
                '#${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF9C27B0),
                  fontSize: 16,
                ),
              ),
            ),
            title: Text(
              name,
              style: const TextStyle(color: ZephyrColors.text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              '$listens plays',
              style: const TextStyle(
                color: ZephyrColors.textDim,
              ),
            ),
          );
        },
      ),
    );
  }
}
