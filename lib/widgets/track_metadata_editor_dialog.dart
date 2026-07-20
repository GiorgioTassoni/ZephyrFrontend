import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../theme/colors.dart';
import 'cover_image.dart';

class TrackMetadataEditorDialog extends StatefulWidget {
  final Track track;

  const TrackMetadataEditorDialog({super.key, required this.track});

  @override
  State<TrackMetadataEditorDialog> createState() => _TrackMetadataEditorDialogState();
}

class _TrackMetadataEditorDialogState extends State<TrackMetadataEditorDialog> with SingleTickerProviderStateMixin {
  final _api = ZephyrApi();
  final _formKey = GlobalKey<FormState>();
  late TabController _tabController;

  final _titleController = TextEditingController();
  final _lyricsController = TextEditingController();
  final _lyricsLrcController = TextEditingController();
  File? _selectedCoverFile;

  List<Map<String, dynamic>> _localArtists = [];
  List<Map<String, dynamic>> _localAlbums = [];
  List<String> _selectedArtistNames = [];
  String? _selectedAlbumId;
  String? _selectedAlbumName;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadFullMetadataAndCatalog();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _lyricsController.dispose();
    _lyricsLrcController.dispose();
    super.dispose();
  }

  Future<void> _loadFullMetadataAndCatalog() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final fullTrack = await _api.getTrackMetadata(widget.track.videoId);
      final artists = await _api.getLocalArtists();
      final albums = await _api.getLocalAlbums();

      setState(() {
        _titleController.text = fullTrack.title;
        _lyricsController.text = fullTrack.lyricsText ?? '';
        _lyricsLrcController.text = fullTrack.lyricsLrc ?? '';
        _localArtists = artists;
        _localAlbums = albums;

        _selectedArtistNames = List<String>.from(fullTrack.artists);

        // Try to match current album
        if (fullTrack.album != null) {
          final albumMatch = albums.firstWhere(
            (e) => e['title'] == fullTrack.album,
            orElse: () => <String, dynamic>{},
          );
          if (albumMatch.isNotEmpty) {
            _selectedAlbumId = albumMatch['browse_id'];
            _selectedAlbumName = albumMatch['title'];
          }
        }

        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _pickCoverFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedCoverFile = File(result.files.single.path!);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick cover: $e'), backgroundColor: ZephyrColors.error),
      );
    }
  }

  void _showArtistSelectionDialog() async {
    final List<String> initialSelected = List<String>.from(_selectedArtistNames);
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: ZephyrColors.bgCard,
              title: const Text('Select Artists'),
              content: SizedBox(
                width: 400,
                child: _localArtists.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Text(
                          'No local artists exist yet.',
                          style: TextStyle(color: ZephyrColors.textDim, fontStyle: FontStyle.italic),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _localArtists.length,
                        itemBuilder: (context, index) {
                          final artist = _localArtists[index];
                          final name = artist['name'] ?? '';
                          final isChecked = initialSelected.contains(name);

                          return CheckboxListTile(
                            title: Text(name),
                            value: isChecked,
                            activeColor: ZephyrColors.primary,
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  initialSelected.add(name);
                                } else {
                                  initialSelected.remove(name);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: ZephyrColors.textDim)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: ZephyrColors.primary),
                  onPressed: () {
                    setState(() {
                      _selectedArtistNames = initialSelected;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Done', style: TextStyle(color: Colors.black)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveMetadata() async {
    if (_selectedArtistNames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one artist.'), backgroundColor: ZephyrColors.error),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // Resolve names to IDs before submit
      final List<String> artistIds = [];
      for (final name in _selectedArtistNames) {
        final matched = _localArtists.firstWhere((a) => a['name'] == name, orElse: () => {});
        final id = matched['id'] as String?;
        if (id != null && id.isNotEmpty) {
          artistIds.add(id);
        } else {
          try {
            final res = await _api.getArtistByName(name);
            final List list = res['artists'] ?? [];
            if (list.isNotEmpty) {
              artistIds.add(list.first['id'] as String);
            }
          } catch (_) {}
        }
      }

      // 1. Update metadata
      await _api.updateTrackMetadata(
        widget.track.videoId,
        title: _titleController.text.trim(),
        artistIds: artistIds.isEmpty ? null : artistIds,
        album: _selectedAlbumName,
        albumId: _selectedAlbumId,
        lyrics: _lyricsController.text.trim(),
        lyricsLrc: _lyricsLrcController.text.trim(),
      );

      // 2. Upload cover if selected
      if (_selectedCoverFile != null) {
        await _api.uploadTrackCover(widget.track.videoId, _selectedCoverFile!);
      }

      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save metadata: $e'), backgroundColor: ZephyrColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ZephyrColors.bgCard,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Edit Track Details', style: TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 500,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: ZephyrColors.primary))
            : _error != null
                ? Center(
                    child: Text(
                      'Failed to load details: $_error',
                      style: const TextStyle(color: ZephyrColors.error),
                    ),
                  )
                : Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TabBar(
                          controller: _tabController,
                          labelColor: ZephyrColors.primary,
                          unselectedLabelColor: ZephyrColors.textDim,
                          indicatorColor: ZephyrColors.primary,
                          dividerColor: Colors.transparent,
                          tabs: const [
                            Tab(text: 'Metadata'),
                            Tab(text: 'Lyrics'),
                            Tab(text: 'Synced LRC'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildMetadataTab(),
                              _buildLyricsTab(),
                              _buildLrcTab(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: ZephyrColors.textDim)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: ZephyrColors.primary,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: _isSaving ? null : _saveMetadata,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                )
              : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildMetadataTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover replacement preview
          Row(
            children: [
              _selectedCoverFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        _selectedCoverFile!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                    )
                  : CoverImage(
                      videoId: widget.track.videoId,
                      size: 64,
                      borderRadius: 6,
                    ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Track Cover Image', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZephyrColors.bgLight,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    onPressed: _pickCoverFile,
                    child: const Text('Choose Image', style: TextStyle(fontSize: 12, color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Track Title *',
              border: OutlineInputBorder(),
            ),
            validator: (val) => val == null || val.trim().isEmpty ? 'Title is required' : null,
          ),
          const SizedBox(height: 20),

          // Restricted Artist Selection
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Artists *',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: ZephyrColors.textDim),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _showArtistSelectionDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: ZephyrColors.bgCard,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade700),
                  ),
                  child: Text(
                    _selectedArtistNames.isEmpty
                        ? 'Select artists'
                        : _selectedArtistNames.join(', '),
                    style: TextStyle(
                      color: _selectedArtistNames.isEmpty ? ZephyrColors.textMuted : Colors.white,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Restricted Album Selection
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Album (Optional)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: ZephyrColors.textDim),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedAlbumId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                hint: const Text('None / Single', style: TextStyle(color: ZephyrColors.textMuted)),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('None / Single', style: TextStyle(color: ZephyrColors.textMuted)),
                  ),
                  ..._localAlbums.map((album) {
                    final title = album['title'] ?? '';
                    final browseId = album['browse_id'] ?? '';
                    return DropdownMenuItem<String>(
                      value: browseId,
                      child: Text(title),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedAlbumId = val;
                    if (val == null) {
                      _selectedAlbumName = null;
                    } else {
                      _selectedAlbumName = _localAlbums.firstWhere((e) => e['browse_id'] == val)['title'];
                    }
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Plain Text Lyrics',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: ZephyrColors.textDim),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TextFormField(
            controller: _lyricsController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Enter plain lyrics here...',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLrcTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Synced LRC Lyrics',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: ZephyrColors.textDim),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TextFormField(
            controller: _lyricsLrcController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '[00:12.50]Line one lyrics\n[00:15.20]Line two lyrics...',
            ),
          ),
        ),
      ],
    );
  }
}
