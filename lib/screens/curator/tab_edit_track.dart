import 'dart:io';
import 'package:flutter/material.dart';
import '../../api/zephyr_api.dart';
import '../../models/models.dart';
import '../../theme/colors.dart';
import 'curator_shared.dart';

/// Tab 2 — Edit metadata of an existing local track.
class EditTrackTab extends StatefulWidget {
  final List<Track> tracks;
  final List<Map<String, dynamic>> artists;
  final List<Map<String, dynamic>> albums;
  final VoidCallback onSuccess;

  const EditTrackTab({
    super.key,
    required this.tracks,
    required this.artists,
    required this.albums,
    required this.onSuccess,
  });

  @override
  State<EditTrackTab> createState() => _EditTrackTabState();
}

class _EditTrackTabState extends State<EditTrackTab> {
  final _api = ZephyrApi();
  final _titleCtrl = TextEditingController();
  final _lyricsCtrl = TextEditingController();
  final _lrcCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  Track? _track;
  File? _cover;
  List<Map<String, dynamic>> _artists = [];
  String? _album;
  bool _busy = false;
  String? _ok;
  String? _err;
  String _searchQuery = '';
  bool _searchOpen = false;
  List<Track> _filteredTracks = [];

  @override
  void didUpdateWidget(EditTrackTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tracks != oldWidget.tracks) {
      _filterTracks(_searchQuery);
    }
  }

  void _filterTracks(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) {
      setState(() {
        _filteredTracks = [];
      });
      return;
    }
    setState(() {
      _filteredTracks = widget.tracks.where((t) {
        final titleMatch = t.title.toLowerCase().contains(q);
        final artistMatch = t.artists.any((a) => a.toLowerCase().contains(q));
        return titleMatch || artistMatch;
      }).toList();
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _lyricsCtrl.dispose();
    _lrcCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onTrackSelected(Track? t) {
    if (t == null) return;
    setState(() {
      _track = t;
      _titleCtrl.text = t.title;
      _artists = [];
      for (int i = 0; i < t.artists.length; i++) {
        final name = t.artists[i];
        String? id = (t.artistsIds.length > i) ? t.artistsIds[i] : null;
        if (id == null || id.isEmpty) {
          final matched = widget.artists.firstWhere((a) => a['name'] == name, orElse: () => {});
          id = matched['id'] as String?;
        }
        _artists.add({'id': id ?? '', 'name': name});
      }
      _album = (t.album?.isNotEmpty ?? false) ? t.album : null;
      _cover = null;
      _ok = null;
      _err = null;
      _lyricsCtrl.clear();
      _lrcCtrl.clear();
      _searchQuery = '';
      _searchCtrl.clear();
      _searchOpen = false;
    });
  }

  void _clearSelection() {
    setState(() {
      _track = null;
      _titleCtrl.clear();
      _artists = [];
      _album = null;
      _cover = null;
      _ok = null;
      _err = null;
      _lyricsCtrl.clear();
      _lrcCtrl.clear();
      _searchQuery = '';
      _searchCtrl.clear();
      _searchOpen = false;
    });
  }

  Future<void> _save() async {
    if (_track == null) {
      setState(() => _err = 'Select a track first.');
      return;
    }
    setState(() {
      _busy = true;
      _ok = null;
      _err = null;
    });
    try {
      final albumId = widget.albums
          .where((a) => a['title'] == _album)
          .map((a) => a['browse_id'] as String?)
          .firstOrNull;

      await _api.updateTrackMetadata(
        _track!.videoId,
        title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
        artistIds: _artists.map((a) => a['id'] as String).where((id) => id.isNotEmpty).toList(),
        album: _album,
        albumId: albumId,
        lyrics: _lyricsCtrl.text.trim().isEmpty ? null : _lyricsCtrl.text.trim(),
        lyricsLrc: _lrcCtrl.text.trim().isEmpty ? null : _lrcCtrl.text.trim(),
      );
      if (_cover != null) {
        try {
          await _api.uploadTrackCover(_track!.videoId, _cover!);
        } catch (_) {}
      }
      setState(() => _ok = 'Track updated!');
      widget.onSuccess();
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Track selector ────────────────────────────
              curatorLabel('Select Track', req: true),
              if (_track == null) ...[
                TapRegion(
                  onTapOutside: (_) {
                    if (_searchOpen) {
                      setState(() => _searchOpen = false);
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        style: const TextStyle(fontSize: 13),
                        decoration: curatorField('', hint: 'Search track by title or artist…'),
                        onChanged: (v) {
                          setState(() {
                            _searchQuery = v;
                            _searchOpen = true;
                          });
                          _filterTracks(v);
                        },
                        onTap: () => setState(() => _searchOpen = true),
                      ),
                      if (_searchOpen) ...[
                        const SizedBox(height: 4),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 220),
                          decoration: BoxDecoration(
                            color: ZephyrColors.bgCard,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: ZephyrColors.bgLight),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 10,
                              )
                            ],
                          ),
                          child: ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            children: () {
                              if (_filteredTracks.isEmpty && _searchQuery.trim().isNotEmpty) {
                                return const [
                                  Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    child: Text(
                                      'No matching tracks found',
                                      style: TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                                    ),
                                  )
                                ];
                              }

                              return _filteredTracks.take(15).map((t) => InkWell(
                                onTap: () => _onTrackSelected(t),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(t.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: ZephyrColors.text)),
                                      const SizedBox(height: 2),
                                      Text(
                                        t.artists.join(', '),
                                        style: const TextStyle(fontSize: 11.5, color: ZephyrColors.textDim),
                                      ),
                                    ],
                                  ),
                                ),
                              )).toList();
                            }(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: ZephyrColors.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ZephyrColors.bgLight),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.audiotrack, color: ZephyrColors.primary, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _track!.title,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ZephyrColors.text),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _track!.artists.join(', '),
                              style: const TextStyle(fontSize: 11.5, color: ZephyrColors.textDim),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.swap_horiz, color: ZephyrColors.primary),
                        tooltip: 'Change Track',
                        onPressed: _clearSelection,
                      ),
                    ],
                  ),
                ),
              ],
              curatorGap,

              if (_track != null) ...[
                // ── Cover + Title ─────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        curatorLabel('Cover Art'),
                        SizedBox(
                          width: 220,
                          child: CuratorFileTile(
                            file: _cover,
                            icon: Icons.image_outlined,
                            noFileText: 'Replace cover',
                            pickLabel: 'Choose Image',
                            onPick: () async {
                              final f = await pickImageFile();
                              if (f != null) setState(() => _cover = f);
                            },
                            onClear: () => setState(() => _cover = null),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          curatorLabel('Title'),
                          TextField(
                            controller: _titleCtrl,
                            style: const TextStyle(fontSize: 13),
                            decoration: curatorField(''),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                curatorGap,

                // ── Artists + Album ────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          curatorLabel('Artists'),
                          CuratorArtistInput(
                            allArtists: widget.artists,
                            selected: _artists,
                            onChange: (v) => setState(() => _artists = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          curatorLabel('Album'),
                          curatorAlbumDrop(widget.albums, _album,
                              (v) => setState(() => _album = v)),
                        ],
                      ),
                    ),
                  ],
                ),
                curatorGap,

                // ── Plain lyrics ───────────────────────────
                curatorLabel('Plain Lyrics (optional)'),
                TextField(
                  controller: _lyricsCtrl,
                  style:
                      const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                  maxLines: 5,
                  decoration:
                      curatorField('', hint: 'Leave blank to keep existing…'),
                ),
                curatorGap,

                // ── LRC lyrics ────────────────────────────
                curatorLabel('Synced Lyrics — LRC (optional)'),
                TextField(
                  controller: _lrcCtrl,
                  style:
                      const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                  maxLines: 5,
                  decoration: curatorField('', hint: '[00:12.00]First line…'),
                ),
                curatorGap,
                const SizedBox(height: 8),

                CuratorSubmitRow(
                  ok: _ok,
                  err: _err,
                  loading: _busy,
                  onTap: _save,
                  label: 'Save Changes',
                  icon: Icons.save_outlined,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
