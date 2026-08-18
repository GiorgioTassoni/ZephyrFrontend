import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../api/zephyr_api.dart';
import '../../theme/colors.dart';
import '../../widgets/toast.dart';
import 'curator_shared.dart';

/// Tab 1 — Upload a new track or import from YouTube Link to the server.
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
  final _targetTrackIdCtrl = TextEditingController();
  final _ytUrlCtrl = TextEditingController();

  File? _audio;
  File? _cover;
  List<Map<String, dynamic>> _artists = [];
  String? _album;
  bool _busy = false;
  String? _ok;
  String? _err;

  bool _ytBusy = false;
  String? _ytOk;
  String? _ytErr;
  Map<String, dynamic>? _ytTrackResult;

  @override
  void initState() {
    super.initState();
    _targetTrackIdCtrl.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _targetTrackIdCtrl.dispose();
    _ytUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    try {
      final r = await FilePicker.platform.pickFiles(
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
    final targetId = _targetTrackIdCtrl.text.trim();
    final isNewTrack = targetId.isEmpty;

    if (isNewTrack && _cover == null) {
      setState(() => _err = 'Cover image is required for new tracks.');
      return;
    }
    if (isNewTrack && _titleCtrl.text.trim().isEmpty) {
      setState(() => _err = 'Please enter a track title or target track ID.');
      return;
    }
    if (isNewTrack && _artists.isEmpty) {
      setState(() => _err = 'Please add at least one artist from local artists.');
      return;
    }

    setState(() {
      _busy = true;
      _ok = null;
      _err = null;
    });
    try {
      await _api.uploadTrack(
        file: _audio!,
        cover: _cover,
        title: _titleCtrl.text.trim().isNotEmpty ? _titleCtrl.text.trim() : null,
        artists: _artists.isNotEmpty ? _artists.map((a) => a['name'] as String).join(', ') : null,
        album: _album,
        targetTrackId: targetId.isNotEmpty ? targetId : null,
        duration: null,
      );

      setState(() {
        _ok = 'Track uploaded successfully!';
        _audio = null;
        _cover = null;
        _artists = [];
        _album = null;
        _titleCtrl.clear();
        _targetTrackIdCtrl.clear();
      });
      if (mounted) {
        ZephyrToast.show(context, 'Track uploaded successfully');
      }
      widget.onSuccess();
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _importFromYouTube() async {
    final url = _ytUrlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _ytErr = 'Please paste a YouTube or YouTube Music URL.');
      return;
    }

    setState(() {
      _ytBusy = true;
      _ytOk = null;
      _ytErr = null;
      _ytTrackResult = null;
    });

    try {
      final res = await _api.addTrackFromYouTube(url);
      final status = res['status']?.toString();
      final title = res['title']?.toString() ?? 'Track';
      String message;
      if (status == 'already_available') {
        message = '"$title" is already available in your library.';
      } else if (status == 'queued') {
        message = '"$title" is already queued for download.';
      } else {
        message = '"$title" added! Audio download queued in background.';
      }

      setState(() {
        _ytOk = message;
        _ytTrackResult = res;
        _ytUrlCtrl.clear();
      });

      if (mounted) {
        ZephyrToast.show(context, message);
      }
      widget.onSuccess();
    } catch (e) {
      setState(() => _ytErr = e.toString());
    } finally {
      setState(() => _ytBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isNewTrack = _targetTrackIdCtrl.text.trim().isEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 8, 40, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Option A: Add from YouTube Link ────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: ZephyrColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ZephyrColors.bgLight.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF0000).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.ondemand_video_rounded, color: Color(0xFFFF4D4D), size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add from YouTube Link',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Paste a YouTube or YouTube Music song URL to automatically import metadata and queue download.',
                          style: TextStyle(fontSize: 12, color: ZephyrColors.textDim),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ytUrlCtrl,
                        style: const TextStyle(fontSize: 13),
                        onSubmitted: (_) => _importFromYouTube(),
                        decoration: curatorField(
                          '',
                          hint: 'https://music.youtube.com/watch?v=... or https://youtu.be/...',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ZephyrColors.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _ytBusy ? null : _importFromYouTube,
                      icon: _ytBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.download_rounded, size: 18),
                      label: Text(_ytBusy ? 'Importing…' : 'Import Track'),
                    ),
                  ],
                ),
                if (_ytErr != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _ytErr!,
                    style: const TextStyle(color: ZephyrColors.error, fontSize: 13),
                  ),
                ],
                if (_ytOk != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _ytOk!,
                    style: const TextStyle(color: ZephyrColors.success, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
                if (_ytTrackResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ZephyrColors.bgLight.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: ZephyrColors.success, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _ytTrackResult!['title']?.toString() ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                (_ytTrackResult!['artists'] as List?)?.join(', ') ?? '',
                                style: const TextStyle(color: ZephyrColors.textDim, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Divider ─────────────────────────────────────────
          Row(
            children: [
              Expanded(child: Divider(color: ZephyrColors.bgLight.withValues(alpha: 0.4))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'OR UPLOAD AUDIO FILE MANUALLY',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: ZephyrColors.textDim.withValues(alpha: 0.7),
                  ),
                ),
              ),
              Expanded(child: Divider(color: ZephyrColors.bgLight.withValues(alpha: 0.4))),
            ],
          ),
          const SizedBox(height: 24),

          // ── Option B: File pickers ──────────────────────────
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
                    curatorLabel(
                      isNewTrack ? 'Cover Art' : 'Cover Art (optional)',
                      req: isNewTrack,
                    ),
                    CuratorFileTile(
                      file: _cover,
                      icon: Icons.image_outlined,
                      noFileText: isNewTrack ? 'Cover image required' : 'No cover art (optional)',
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

          // ── Target Track ID (Optional Fulfill) ───────────────
          curatorLabel('Target Track ID (optional fulfill for dz_... tracks)'),
          TextField(
            controller: _targetTrackIdCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: curatorField('e.g. dz_1297319772'),
          ),
          curatorGap,

          // ── Song Title (Full width) ───────────────────
          curatorLabel('Song Title', req: isNewTrack),
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
                    curatorLabel('Artists', req: isNewTrack),
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
    );
  }
}
