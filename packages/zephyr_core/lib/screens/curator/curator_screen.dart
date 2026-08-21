import 'package:flutter/material.dart';
import '../../api/zephyr_api.dart';
import '../../models/models.dart';
import '../../theme/colors.dart';
import 'curator_shared.dart';
import 'tab_upload_track.dart';
import 'tab_edit_track.dart';
import 'tab_create_album.dart';
import 'tab_create_artist.dart';

/// Curator Studio — root screen that owns shared data loading
/// and delegates rendering to the four tab widgets.
class CuratorScreen extends StatefulWidget {
  const CuratorScreen({super.key});

  @override
  State<CuratorScreen> createState() => _CuratorScreenState();
}

class _CuratorScreenState extends State<CuratorScreen> {
  final _api = ZephyrApi();

  List<Map<String, dynamic>> _artists = [];
  List<Map<String, dynamic>> _albums = [];
  List<Track> _tracks = [];
  bool _loading = true;
  String? _err;
  int _tab = 0;

  static const _tabLabels = ['Artist', 'Album', 'Track', 'Edit Track'];
  static const _titles = [
    'Create Local Artist',
    'Create Local Album',
    'Upload a Track',
    'Edit Existing Track',
  ];
  static const _subtitles = [
    'Create a new artist profile with bio and avatar.',
    'Group local tracks into a new album.',
    'Upload MP3/M4A/FLAC. Artists and albums must already exist.',
    'Update metadata or lyrics for a local track.',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _err = null; });
    try {
      final a = await _api.getLocalArtists();
      final b = await _api.getLocalAlbums();
      final c = await _api.getDownloadedTracks();
      setState(() {
        _artists = a; _albums = b; _tracks = c; _loading = false;
      });
    } catch (e) {
      setState(() { _err = e.toString(); _loading = false; });
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
                  'The Curator Studio contains track uploading & metadata tools designed for desktop screens. Please access Zephyr from your computer to use these tools.',
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

    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: ZephyrColors.primary));
    }
    if (_err != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Error: $_err',
              style: const TextStyle(color: ZephyrColors.error)),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: ZephyrColors.primary),
            onPressed: _load,
            child:
                const Text('Retry', style: TextStyle(color: Colors.black)),
          ),
        ]),
      );
    }

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header & Stats ───────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _titles[_tab],
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _subtitles[_tab],
                            style: const TextStyle(
                              color: ZephyrColors.textDim,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    CuratorPillBar(
                      labels: _tabLabels,
                      icons: const [
                        Icons.person_add_rounded,
                        Icons.album_rounded,
                        Icons.upload_file_rounded,
                        Icons.edit_note_rounded,
                      ],
                      selected: _tab,
                      onTap: (i) => setState(() => _tab = i),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Overview Stats Bar
                Row(
                  children: [
                    _buildStatChip(
                      icon: Icons.person_rounded,
                      label: 'Local Artists',
                      value: '${_artists.length}',
                      color: ZephyrColors.primary,
                    ),
                    const SizedBox(width: 12),
                    _buildStatChip(
                      icon: Icons.album_rounded,
                      label: 'Local Albums',
                      value: '${_albums.length}',
                      color: const Color(0xFF00E5FF),
                    ),
                    const SizedBox(width: 12),
                    _buildStatChip(
                      icon: Icons.audiotrack_rounded,
                      label: 'Local Tracks',
                      value: '${_tracks.length}',
                      color: ZephyrColors.success,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Tab content ───────────────────────────────
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                CreateArtistTab(onSuccess: _load),
                CreateAlbumTab(
                  artists: _artists,
                  tracks: _tracks,
                  onSuccess: _load,
                ),
                UploadTrackTab(
                  artists: _artists,
                  albums: _albums,
                  onSuccess: _load,
                ),
                EditTrackTab(
                  tracks: _tracks,
                  artists: _artists,
                  albums: _albums,
                  onSuccess: _load,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: ZephyrColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ZephyrColors.bgLight.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: ZephyrColors.textDim),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
