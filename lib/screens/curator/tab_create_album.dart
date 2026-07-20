import 'dart:io';
import 'package:flutter/material.dart';
import '../../api/zephyr_api.dart';
import '../../models/models.dart';
import '../../theme/colors.dart';
import 'curator_shared.dart';

/// Tab 3 — Create a new local album from existing tracks.
class CreateAlbumTab extends StatefulWidget {
  final List<Map<String, dynamic>> artists;
  final List<Track> tracks;
  final VoidCallback onSuccess;

  const CreateAlbumTab({
    super.key,
    required this.artists,
    required this.tracks,
    required this.onSuccess,
  });

  @override
  State<CreateAlbumTab> createState() => _CreateAlbumTabState();
}

class _CreateAlbumTabState extends State<CreateAlbumTab> {
  final _api = ZephyrApi();
  final _titleCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  File? _cover;
  List<Map<String, dynamic>> _artists = [];
  List<Track> _selectedTracks = [];
  bool _busy = false;
  String? _ok;
  String? _err;
  String _searchQuery = '';
  List<Track> _filteredTracks = [];
  bool _searchOpen = false;

  @override
  void didUpdateWidget(CreateAlbumTab oldWidget) {
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
    _yearCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _err = 'Album title required.');
      return;
    }
    if (_selectedTracks.isEmpty) {
      setState(() => _err = 'At least one track is required to create an album.');
      return;
    }
    setState(() {
      _busy = true;
      _ok = null;
      _err = null;
    });
    try {
      final res = await _api.createLocalAlbum(
        title: _titleCtrl.text.trim(),
        artistIds: _artists.map((a) => a['id'] as String).where((id) => id.isNotEmpty).toList(),
        year: int.tryParse(_yearCtrl.text.trim()) ?? DateTime.now().year,
        trackIds: _selectedTracks.map((t) => t.videoId).toList(),
      );
      final bid = res['browse_id'] as String?;
      if (_cover != null && bid != null) {
        try {
          await _api.uploadAlbumCover(bid, _cover!);
        } catch (_) {}
      }
      setState(() {
        _ok = 'Album created!';
        _titleCtrl.clear();
        _yearCtrl.clear();
        _searchCtrl.clear();
        _searchQuery = '';
        _filteredTracks = [];
        _cover = null;
        _artists = [];
        _selectedTracks = [];
      });
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
              // ── Cover + Title + Artists + Year ────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      curatorLabel('Cover (optional)'),
                      SizedBox(
                        width: 220,
                        child: CuratorFileTile(
                          file: _cover,
                          icon: Icons.image_outlined,
                          noFileText: 'No cover',
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
                        curatorLabel('Album Title', req: true),
                        TextField(
                          controller: _titleCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: curatorField(''),
                        ),
                        curatorGap,
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
                                      onChange: (v) =>
                                          setState(() => _artists = v),
                                    ),
                                  ]),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 110,
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    curatorLabel('Year'),
                                    TextField(
                                      controller: _yearCtrl,
                                      style: const TextStyle(fontSize: 13),
                                      keyboardType: TextInputType.number,
                                      decoration: curatorField('',
                                          hint: '${DateTime.now().year}'),
                                    ),
                                  ]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              curatorGap,

              // ── Track search and selection ───────────────────────────
              curatorLabel('Include Tracks', req: true),
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
                      style: const TextStyle(fontSize: 13),
                      decoration: curatorField('', hint: 'Search and add tracks to album…'),
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
                        constraints: const BoxConstraints(maxHeight: 200),
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

                            // Filter out already selected tracks from suggestions
                            final availableSuggestions = _filteredTracks
                                .where((t) => !_selectedTracks.any((s) => s.videoId == t.videoId))
                                .toList();

                            if (availableSuggestions.isEmpty && _searchQuery.trim().isNotEmpty) {
                              return const [
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Text(
                                    'All matching tracks are already added',
                                    style: TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                                  ),
                                )
                              ];
                            }

                            return availableSuggestions.take(15).map((t) => InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedTracks.add(t);
                                  _searchQuery = '';
                                  _searchCtrl.clear();
                                  _searchOpen = false;
                                });
                              },
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
              curatorGap,

              // ── Selected Tracks List ───────────────────────────
              if (_selectedTracks.isNotEmpty) ...[
                curatorLabel('Selected Tracks (${_selectedTracks.length})'),
                Material(
                  color: ZephyrColors.bgCard,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                    side: BorderSide(
                        color: ZephyrColors.bgLight.withValues(alpha: 0.5)),
                  ),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _selectedTracks.length,
                      itemBuilder: (context, index) {
                        final t = _selectedTracks[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.audiotrack, color: ZephyrColors.primary, size: 18),
                          title: Text(t.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          subtitle: Text(t.artists.join(', '), style: const TextStyle(fontSize: 11, color: ZephyrColors.textDim)),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: ZephyrColors.error, size: 18),
                            onPressed: () {
                              setState(() {
                                _selectedTracks.removeAt(index);
                              });
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
                curatorGap,
              ],
              const SizedBox(height: 8),

              CuratorSubmitRow(
                ok: _ok,
                err: _err,
                loading: _busy,
                onTap: _create,
                label: 'Create Album',
                icon: Icons.album_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
