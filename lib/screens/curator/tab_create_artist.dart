import 'dart:io';
import 'package:flutter/material.dart';
import '../../api/zephyr_api.dart';
import 'curator_shared.dart';

/// Tab 4 — Create a new local artist profile.
class CreateArtistTab extends StatefulWidget {
  final VoidCallback onSuccess;

  const CreateArtistTab({super.key, required this.onSuccess});

  @override
  State<CreateArtistTab> createState() => _CreateArtistTabState();
}

class _CreateArtistTabState extends State<CreateArtistTab> {
  final _api = ZephyrApi();
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  File? _avatar;
  bool _busy = false;
  String? _ok;
  String? _err;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _err = 'Artist name required.');
      return;
    }
    setState(() {
      _busy = true;
      _ok = null;
      _err = null;
    });
    try {
      final res = await _api.createLocalArtist(
        name: _nameCtrl.text.trim(),
        bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
      );
      final aid = res['artist_id'] as String?;
      if (_avatar != null && aid != null) {
        try {
          await _api.uploadArtistCover(aid, _avatar!);
        } catch (_) {}
      }
      setState(() {
        _ok = 'Artist created!';
        _nameCtrl.clear();
        _bioCtrl.clear();
        _avatar = null;
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
              // ── Avatar + Name + Bio ───────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      curatorLabel('Avatar (optional)'),
                      SizedBox(
                        width: 220,
                        child: CuratorFileTile(
                          file: _avatar,
                          icon: Icons.person_outline,
                          noFileText: 'No avatar',
                          pickLabel: 'Choose Image',
                          onPick: () async {
                            final f = await pickImageFile();
                            if (f != null) setState(() => _avatar = f);
                          },
                          onClear: () => setState(() => _avatar = null),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        curatorLabel('Artist Name', req: true),
                        TextField(
                          controller: _nameCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: curatorField(''),
                        ),
                        curatorGap,
                        curatorLabel('Biography (optional)'),
                        TextField(
                          controller: _bioCtrl,
                          style: const TextStyle(fontSize: 13),
                          maxLines: 4,
                          decoration: curatorField('',
                              hint: 'Short description of the artist…'),
                        ),
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
                onTap: _create,
                label: 'Create Artist',
                icon: Icons.person_add_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
