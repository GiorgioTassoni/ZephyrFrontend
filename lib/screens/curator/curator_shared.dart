// Shared UI helpers for the Curator Studio screens.
// Imported by all curator tab files.
import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../api/zephyr_api.dart';
import '../../widgets/toast.dart';

// ─── Dashed Border Painter for Empty File Tiles ──────────────────────────────

class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double dashLength;
  final double borderRadius;

  DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.0,
    this.gap = 5.0,
    this.dashLength = 6.0,
    this.borderRadius = 10.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(borderRadius),
      ));

    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double nextDistance = distance + dashLength;
        canvas.drawPath(
          metric.extractPath(
              distance, nextDistance.clamp(0.0, metric.length)),
          paint,
        );
        distance = nextDistance + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.gap != gap ||
      oldDelegate.dashLength != dashLength ||
      oldDelegate.borderRadius != borderRadius;
}

// ─── Field decoration ────────────────────────────────────────────────────────

InputDecoration curatorField(String label, {String? hint}) => InputDecoration(
      labelText: label.isEmpty ? null : label,
      hintText: hint,
      labelStyle: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
      hintStyle: const TextStyle(color: ZephyrColors.textMuted, fontSize: 13),
      filled: true,
      fillColor: ZephyrColors.bgLight,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: ZephyrColors.bgLight.withValues(alpha: 0.7))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: ZephyrColors.primary, width: 1.5)),
    );

// ─── Spacing constants ────────────────────────────────────────────────────────

const curatorGap = SizedBox(height: 14);

// ─── Field label ─────────────────────────────────────────────────────────────

Widget curatorLabel(String text, {bool req = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text.rich(TextSpan(
        text: text,
        style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: ZephyrColors.textDim),
        children: req
            ? const [
                TextSpan(
                    text: ' *',
                    style: TextStyle(color: ZephyrColors.primary))
              ]
            : [],
      )),
    );

// ─── Album dropdown ──────────────────────────────────────────────────────────

Widget curatorAlbumDrop(
  List<Map<String, dynamic>> albums,
  String? selected,
  ValueChanged<String?> onChange,
) {
  // Filter the albums to keep only unique titles to avoid duplicate value crashes.
  final Map<String, Map<String, dynamic>> uniqueAlbums = {};
  for (final a in albums) {
    final title = a['title'] as String?;
    if (title != null && title.isNotEmpty) {
      uniqueAlbums[title] = a;
    }
  }

  // Ensure that if `selected` is not null and not present in the unique list,
  // we add it to the list of items so that the dropdown doesn't crash on invalid/unloaded values.
  final items = <DropdownMenuItem<String>>[
    const DropdownMenuItem(value: null, child: Text('None / Single')),
    ...uniqueAlbums.values.map((a) {
      final title = a['title'] as String;
      return DropdownMenuItem(
        value: title,
        child: Text(title, overflow: TextOverflow.ellipsis),
      );
    }),
  ];

  final bool hasSelected = selected != null && uniqueAlbums.containsKey(selected);
  if (selected != null && !hasSelected) {
    items.add(DropdownMenuItem(
      value: selected,
      child: Text(selected, overflow: TextOverflow.ellipsis),
    ));
  }

  return DropdownButtonFormField<String>(
    value: selected,
    decoration: curatorField(''), // Empty label to avoid double label
    dropdownColor: ZephyrColors.bgCard,
    isDense: true,
    isExpanded: true,
    style: const TextStyle(fontSize: 13, color: ZephyrColors.text),
    items: items,
    onChanged: onChange,
  );
}

// ─── File picker tile (enhanced 120px height) ────────────────────────────────

class CuratorFileTile extends StatelessWidget {
  final File? file;
  final IconData icon;
  final String noFileText;
  final String pickLabel;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const CuratorFileTile({
    super.key,
    required this.file,
    required this.icon,
    required this.noFileText,
    required this.pickLabel,
    required this.onPick,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final has = file != null;
    return Container(
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
      ),
      child: has ? _filled(context) : _empty(),
    );
  }

  Widget _filled(BuildContext context) {
    // Premium dark blueish/grey tint for selected state
    return Container(
      decoration: BoxDecoration(
        color: ZephyrColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ZephyrColors.primary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: ZephyrColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 24, color: ZephyrColors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file!.path.split('/').last,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ZephyrColors.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                FutureBuilder<int>(
                  future: file!.length(),
                  builder: (context, snapshot) {
                    final bytes = snapshot.data ?? 0;
                    final mb = (bytes / (1024 * 1024)).toStringAsFixed(2);
                    return Text(
                      bytes > 0 ? '$mb MB • Selected' : 'Selected',
                      style: const TextStyle(
                          fontSize: 11.5, color: ZephyrColors.textMuted),
                    );
                  },
                ),
              ],
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onClear,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: ZephyrColors.bgLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close,
                    size: 16, color: ZephyrColors.textDim),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _empty() {
    return CustomPaint(
      painter: DashedBorderPainter(
        color: ZephyrColors.bgLight.withValues(alpha: 0.8),
        strokeWidth: 1.5,
      ),
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: ZephyrColors.textMuted),
            const SizedBox(height: 6),
            Text(
              noFileText,
              style:
                  const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onPick,
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: ZephyrColors.primary.withValues(alpha: 0.5)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              child: Text(
                pickLabel,
                style: const TextStyle(
                    color: ZephyrColors.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Artist chip input (Autocompletion restrict suggestions only) ───────────

class CuratorArtistInput extends StatefulWidget {
  final List<Map<String, dynamic>> allArtists;
  final List<Map<String, dynamic>> selected;
  final ValueChanged<List<Map<String, dynamic>>> onChange;

  const CuratorArtistInput({
    super.key,
    required this.allArtists,
    required this.selected,
    required this.onChange,
  });

  @override
  State<CuratorArtistInput> createState() => _CuratorArtistInputState();
}

class _CuratorArtistInputState extends State<CuratorArtistInput> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String _q = '';
  bool _open = false;
  List<Map<String, dynamic>> _directoryArtists = [];
  bool _loadingDir = false;

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    setState(() => _loadingDir = true);
    try {
      final res = await ZephyrApi().getArtistsDirectory(limit: 200);
      final List list = res['artists'] ?? [];
      setState(() {
        _directoryArtists = list.map((e) => Map<String, dynamic>.from(e)).toList();
      });
    } catch (_) {
      _directoryArtists = widget.allArtists;
    } finally {
      setState(() => _loadingDir = false);
    }
  }

  List<Map<String, dynamic>> get _suggestions {
    final selectedNames = widget.selected.map((a) => a['name'] as String).toSet();
    final sourceList = _directoryArtists.isNotEmpty ? _directoryArtists : widget.allArtists;
    return sourceList
        .where((a) =>
            !selectedNames.contains(a['name']) &&
            (a['name'] as String).toLowerCase().contains(_q.toLowerCase()))
        .toList();
  }

  void _add(Map<String, dynamic> artist) {
    widget.onChange([...widget.selected, artist]);
    _ctrl.clear();
    setState(() {
      _q = '';
      _open = false;
    });
  }

  void _remove(Map<String, dynamic> artist) {
    widget.onChange(widget.selected.where((x) => x['name'] != artist['name']).toList());
  }

  Future<void> _resolveAndAdd() async {
    final queryName = _q.trim();
    if (queryName.isEmpty) return;
    setState(() => _open = false);
    setState(() => _loadingDir = true);
    try {
      final res = await ZephyrApi().getArtistByName(queryName);
      final List list = res['artists'] ?? [];
      if (list.isNotEmpty) {
        final artist = Map<String, dynamic>.from(list.first);
        _add(artist);
      } else {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: ZephyrColors.bgCard,
              title: const Text('Artist Not Found'),
              content: Text('Artist "$queryName" was not found in the unified directory. Create them under the Artist tab first.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ZephyrToast.show(context, 'Lookup failed: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingDir = false);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      onTapOutside: (_) {
        if (_open) {
          setState(() => _open = false);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Chips (only when artists are selected)
          if (widget.selected.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: widget.selected
                  .map((a) => Chip(
                        label: Text(a['name'] as String,
                            style: const TextStyle(
                                fontSize: 12, color: ZephyrColors.text)),
                        backgroundColor:
                            ZephyrColors.primary.withValues(alpha: 0.18),
                        side: BorderSide(
                            color:
                                ZephyrColors.primary.withValues(alpha: 0.45)),
                        deleteIconColor: ZephyrColors.primary,
                        onDeleted: () => _remove(a),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 6),
          ],

          // Search text field
          TextField(
            controller: _ctrl,
            focusNode: _focus,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: widget.selected.isEmpty
                  ? 'Search and add artist from directory…'
                  : 'Add another artist…',
              hintStyle: const TextStyle(
                  color: ZephyrColors.textMuted, fontSize: 13),
              filled: true,
              fillColor: ZephyrColors.bgLight,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: ZephyrColors.bgLight.withValues(alpha: 0.7))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                      color: ZephyrColors.primary, width: 1.5)),
            ),
            onChanged: (v) => setState(() {
              _q = v;
              _open = true; // Always show suggestions area when user is typing
            }),
            onTap: () => setState(() => _open = true),
            onSubmitted: (_) => _resolveAndAdd(),
          ),

          // Dropdown suggestions or lookup action
          if (_open) ...[
            if (_suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                constraints: const BoxConstraints(maxHeight: 160),
                decoration: BoxDecoration(
                  color: ZephyrColors.bgCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ZephyrColors.bgLight),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 10)
                  ],
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: _suggestions
                      .map((a) => InkWell(
                            onTap: () => _add(a),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 9),
                              child: Text(a['name'] as String,
                                  style: const TextStyle(fontSize: 13)),
                            ),
                          ))
                      .toList(),
                ),
              )
            else if (_q.trim().isNotEmpty)
              InkWell(
                onTap: _resolveAndAdd,
                child: Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: ZephyrColors.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ZephyrColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      if (_loadingDir)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      else
                        const Icon(Icons.search, color: ZephyrColors.primary, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Lookup exact match for "$_q" in directory...',
                          style: const TextStyle(fontSize: 13, color: ZephyrColors.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─── Submit row (status + button) ────────────────────────────────────────────

class CuratorSubmitRow extends StatelessWidget {
  final String? ok;
  final String? err;
  final bool loading;
  final VoidCallback onTap;
  final String label;
  final IconData icon;

  const CuratorSubmitRow({
    super.key,
    this.ok,
    this.err,
    required this.loading,
    required this.onTap,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: ok != null
            ? Row(children: [
                const Icon(Icons.check_circle_outline,
                    size: 14, color: ZephyrColors.success),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(ok!,
                        style: const TextStyle(
                            color: ZephyrColors.success, fontSize: 12))),
              ])
            : err != null
                ? Row(children: [
                    const Icon(Icons.error_outline,
                        size: 14, color: ZephyrColors.error),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(err!,
                            style: const TextStyle(
                                color: ZephyrColors.error, fontSize: 12))),
                  ])
                : const SizedBox.shrink(),
      ),
      const SizedBox(width: 16),
      loading
          ? const SizedBox(
              width: 130,
              height: 3,
              child: LinearProgressIndicator(
                  color: ZephyrColors.primary,
                  backgroundColor: ZephyrColors.bgLight),
            )
          : ElevatedButton.icon(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: ZephyrColors.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                    horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              icon: Icon(icon, size: 15),
              label: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
            ),
    ]);
  }
}

// ─── Pill tab bar ─────────────────────────────────────────────────────────────

class CuratorPillBar extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onTap;

  const CuratorPillBar({
    super.key,
    required this.labels,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ZephyrColors.bgCard,
        borderRadius: BorderRadius.circular(11),
        border:
            Border.all(color: ZephyrColors.bgLight.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(labels.length, (i) {
          final active = i == selected;
          return GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: active ? ZephyrColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight:
                      active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? Colors.black : ZephyrColors.textDim,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Helper: pick image file ──────────────────────────────────────────────────

Future<File?> pickImageFile() async {
  try {
    final r =
        await FilePicker.pickFiles(type: FileType.image, allowMultiple: false);
    if (r?.files.single.path != null) return File(r!.files.single.path!);
  } catch (_) {}
  return null;
}
