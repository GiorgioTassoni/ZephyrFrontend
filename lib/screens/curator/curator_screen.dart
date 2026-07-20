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
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ───────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 28, 40, 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_titles[_tab],
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4)),
                      const SizedBox(height: 4),
                      Text(_subtitles[_tab],
                          style: const TextStyle(
                              color: ZephyrColors.textDim, fontSize: 13)),
                    ]),
              ),
              const SizedBox(width: 24),
              CuratorPillBar(
                labels: _tabLabels,
                selected: _tab,
                onTap: (i) => setState(() => _tab = i),
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
                  artists: _artists, tracks: _tracks, onSuccess: _load),
              UploadTrackTab(
                  artists: _artists, albums: _albums, onSuccess: _load),
              EditTrackTab(
                  tracks: _tracks,
                  artists: _artists,
                  albums: _albums,
                  onSuccess: _load),
            ],
          ),
        ),
      ]),
    );
  }
}
