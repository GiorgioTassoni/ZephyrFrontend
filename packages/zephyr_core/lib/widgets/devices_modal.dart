import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../providers/player_provider.dart';
import '../theme/colors.dart';
import '../utils/device_info.dart';
import 'toast.dart';

class DevicesModal extends ConsumerStatefulWidget {
  const DevicesModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ZephyrColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const DevicesModal(),
    );
  }

  @override
  ConsumerState<DevicesModal> createState() => _DevicesModalState();
}

class _DevicesModalState extends ConsumerState<DevicesModal> {
  final _api = ZephyrApi();
  final TextEditingController _nameController = TextEditingController();
  bool _isEditingName = false;
  bool _isLoadingDevices = false;

  @override
  void initState() {
    super.initState();
    final playerState = ref.read(playerProvider);
    _nameController.text = playerState.myDeviceName;
    if (playerState.connectedDevices.isEmpty) {
      _fetchDevices();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _fetchDevices() async {
    setState(() => _isLoadingDevices = true);
    try {
      final devices = await _api.getConnectedDevices();
      final playerNotifier = ref.read(playerProvider.notifier);
      playerNotifier.updateConnectedDevices(devices);
      if (mounted) {
        setState(() {
          _isLoadingDevices = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingDevices = false;
        });
      }
    }
  }

  Future<void> _saveDeviceName() async {
    final newName = _nameController.text.trim();
    if (newName.isNotEmpty) {
      await DeviceInfo.setDeviceName(newName);
      final playerNotifier = ref.read(playerProvider.notifier);
      playerNotifier.updateDeviceName(newName);
      if (mounted) {
        setState(() {
          _isEditingName = false;
        });
        ZephyrToast.show(context, 'Device name updated to "$newName"');
        _fetchDevices();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final playerNotifier = ref.read(playerProvider.notifier);
    final isOwner = playerState.isPlayerDevice;
    final activeDeviceName = playerState.activeDeviceName ?? 'Unknown Device';

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ZephyrColors.bgLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Header Title
              const Row(
                children: [
                  Icon(Icons.devices_rounded, color: ZephyrColors.primary, size: 28),
                  SizedBox(width: 12),
                  Text(
                    'Connect to a Device',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: ZephyrColors.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Listen to music and control playback seamlessly across your devices.',
                style: TextStyle(fontSize: 13, color: ZephyrColors.textDim),
              ),
              const SizedBox(height: 20),

              // Connected Devices Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'CONNECTED DEVICES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: ZephyrColors.textDim,
                    ),
                  ),
                  if (_isLoadingDevices)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: ZephyrColors.primary),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              if (playerState.connectedDevices.isNotEmpty) ...[
                ...playerState.connectedDevices.map((dev) {
                  final String devId = dev['device_id']?.toString() ?? '';
                  final String devName = dev['device_name']?.toString() ?? 'Device';
                  final bool isDevPlayer = dev['is_player'] == true;
                  final bool isDevAlive = dev['is_alive'] == true;
                  final bool isThisDevice = devId == playerState.myDeviceId;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDevPlayer
                          ? ZephyrColors.primary.withValues(alpha: 0.15)
                          : ZephyrColors.bgLight.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDevPlayer
                            ? ZephyrColors.primary.withValues(alpha: 0.5)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isDevPlayer
                              ? Icons.volume_up_rounded
                              : (devName.toLowerCase().contains('phone') || devName.toLowerCase().contains('mobile')
                                  ? Icons.smartphone_rounded
                                  : Icons.laptop_chromebook),
                          color: isDevPlayer ? ZephyrColors.primary : ZephyrColors.textDim,
                          size: 24,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      devName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: isDevPlayer ? ZephyrColors.primary : ZephyrColors.text,
                                      ),
                                    ),
                                  ),
                                  if (isThisDevice) ...[
                                    const SizedBox(width: 6),
                                    const Text('(This device)', style: TextStyle(fontSize: 11, color: ZephyrColors.textDim)),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isDevPlayer
                                    ? 'Active Speaker'
                                    : (isDevAlive ? 'Online • Ready' : 'Standby'),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDevPlayer ? ZephyrColors.primary : ZephyrColors.textDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isDevPlayer && isThisDevice)
                          ElevatedButton(
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await playerNotifier.takeoverPlayback(force: true);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ZephyrColors.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Play Here', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  );
                }),
              ] else ...[
                // Fallback Active Speaker Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isOwner
                        ? ZephyrColors.primary.withValues(alpha: 0.15)
                        : ZephyrColors.bgLight.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isOwner
                          ? ZephyrColors.primary.withValues(alpha: 0.5)
                          : ZephyrColors.bgLight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOwner ? Icons.speaker_rounded : Icons.laptop_chromebook,
                        color: isOwner ? ZephyrColors.primary : ZephyrColors.text,
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    isOwner ? playerState.myDeviceName : activeDeviceName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: ZephyrColors.text,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isOwner ? Colors.green : ZephyrColors.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isOwner ? 'Active Speaker' : 'Playing Remotely',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isOwner ? 'Audio is currently playing on this device.' : 'Audio is playing on $activeDeviceName.',
                              style: const TextStyle(fontSize: 12, color: ZephyrColors.textDim),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // "This Device" Card
              const Text(
                'THIS DEVICE NAME',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: ZephyrColors.textDim,
                ),
              ),
              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: ZephyrColors.bgLight.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phonelink, color: ZephyrColors.textDim, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _isEditingName
                          ? TextField(
                              controller: _nameController,
                              autofocus: true,
                              style: const TextStyle(color: ZephyrColors.text, fontSize: 14),
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: 'Enter device name',
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _saveDeviceName(),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  playerState.myDeviceName.isNotEmpty
                                      ? playerState.myDeviceName
                                      : 'This Device',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: ZephyrColors.text,
                                  ),
                                ),
                                Text(
                                  isOwner ? 'Controlling local audio' : 'Remote Controller',
                                  style: const TextStyle(fontSize: 11, color: ZephyrColors.textDim),
                                ),
                              ],
                            ),
                    ),
                    if (_isEditingName)
                      IconButton(
                        icon: const Icon(Icons.check, color: ZephyrColors.primary, size: 20),
                        onPressed: _saveDeviceName,
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: ZephyrColors.textDim, size: 18),
                        tooltip: 'Rename device',
                        onPressed: () {
                          setState(() {
                            _isEditingName = true;
                          });
                        },
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Action Button (Takeover or Active confirmation)
              if (!isOwner)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await playerNotifier.takeoverPlayback(force: true);
                    },
                    icon: const Icon(Icons.volume_up, color: Colors.black),
                    label: const Text(
                      'Play on This Device',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZephyrColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Currently Playing Here',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
