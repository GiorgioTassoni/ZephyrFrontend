import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../api/zephyr_api.dart';
import 'curator_shared.dart';

/// Tab 1 — Upload a new track to the server.
class UploadTrackTab extends StatefulWidget {
  final List<Map<String, dynamic>> artists;
  final List<Map<String, dynamic>> albums;
  final VoidCallback onSuccess;

  const UploadTrackTab({
    super.key,
    required this.artists,
    required this.albums,
    required this.onSuccess,
  });

  @override
  State<UploadTrackTab> createState() => _UploadTrackTabState();
}

class _UploadTrackTabState extends State<UploadTrackTab> {
  final _api = ZephyrApi();
  final _titleCtrl = TextEditingController();

  File? _audio;
  File? _cover;
  List<Map<String, dynamic>> _artists = [];
  String? _album;
  bool _busy = false;
  String? _ok;
  String? _err;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    try {
      final r = await FilePicker.pickFiles(
          type: FileType.audio, allowMultiple: false);
      if (r?.files.single.path != null) {
        setState(() => _audio = File(r!.files.single.path!));
      }
    } catch (_) {}
  }

  Future<void> _upload() async {
    if (_audio == null) {
      setState(() => _err = 'Please select an audio file.');
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _err = 'Please enter a track title.');
      return;
    }
    if (_artists.isEmpty) {
      setState(() => _err = 'Please add at least one artist from local artists.');
      return;
    }

    setState(() {
      _busy = true;
      _ok = null;
      _err = null;
    });
    try {
      final res = await _api.uploadTrack(
        file: _audio!,
        title: _titleCtrl.text.trim(),
        artists: _artists.map((a) => a['name'] as String).join(', '),
        album: _album,
        duration: null, // Extracted from file metadata on the backend
      );
      final tid = res['track_id'] as String?;
      if (_cover != null && tid != null) {
        try {
          await _api.uploadTrackCover(tid, _cover!);
        } catch (_) {}
      }
      setState(() {
        _ok = 'Track uploaded successfully!';
        _audio = null;
        _cover = null;
        _artists = [];
        _album = null;
        _titleCtrl.clear();
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
              // ── File pickers ──────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        curatorLabel('Audio File', req: true),
                        CuratorFileTile(
                          file: _audio,
                          icon: Icons.audio_file_outlined,
                          noFileText: 'No audio file selected',
                          pickLabel: 'Choose Audio File',
                          onPick: _pickAudio,
                          onClear: () => setState(() => _audio = null),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        curatorLabel('Cover Art (optional)'),
                        CuratorFileTile(
                          file: _cover,
                          icon: Icons.image_outlined,
                          noFileText: 'No cover art (optional)',
                          pickLabel: 'Choose Image',
                          onPick: () async {
                            final f = await pickImageFile();
                            if (f != null) setState(() => _cover = f);
                          },
                          onClear: () => setState(() => _cover = null),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              curatorGap,

              // ── Song Title (Full width) ───────────────────
              curatorLabel('Song Title', req: true),
              TextField(
                controller: _titleCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: curatorField(''),
              ),
              curatorGap,

              // ── Artists + Album ───────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        curatorLabel('Artists', req: true),
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
              const SizedBox(height: 8),

              CuratorSubmitRow(
                ok: _ok,
                err: _err,
                loading: _busy,
                onTap: _upload,
                label: 'Upload to Library',
                icon: Icons.cloud_upload_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
