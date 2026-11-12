import 'package:material_ui/material_ui.dart';

import 'style.dart';

/// What the user asked for from the settings sheet.
enum SettingsAction { changeImage, adjustImage }

class Settings {
  const Settings({
    required this.timeoutSeconds,
    required this.showOnLockScreen,
  });

  final int timeoutSeconds;
  final bool showOnLockScreen;

  static const defaults = Settings(timeoutSeconds: 60, showOnLockScreen: true);

  static Future<Settings> load() async {
    try {
      final m = await native.invokeMapMethod<String, Object?>('settings');
      if (m == null) return defaults;
      return Settings(
        timeoutSeconds: (m['timeoutSeconds'] as int?) ?? 60,
        showOnLockScreen: (m['showOnLockScreen'] as bool?) ?? true,
      );
    } catch (_) {
      return defaults;
    }
  }

  Settings copyWith({int? timeoutSeconds, bool? showOnLockScreen}) => Settings(
    timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    showOnLockScreen: showOnLockScreen ?? this.showOnLockScreen,
  );
}

const timeoutChoices = [30, 60, 120];

/// Bottom sheet opened by long-pressing the card. Changes to the timeout and
/// lock-screen switch are saved immediately through [onChanged].
Future<SettingsAction?> showSettingsSheet(
  BuildContext context, {
  required Settings settings,
  required bool canAdjust,
  required ValueChanged<Settings> onChanged,
}) {
  return showModalBottomSheet<SettingsAction>(
    context: context,
    backgroundColor: kSheet,
    barrierColor: const Color(0x99000000),
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _SettingsSheet(
      initial: settings,
      canAdjust: canAdjust,
      onChanged: onChanged,
    ),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({
    required this.initial,
    required this.canAdjust,
    required this.onChanged,
  });

  final Settings initial;
  final bool canAdjust;
  final ValueChanged<Settings> onChanged;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late Settings _s = widget.initial;

  void _update(Settings s) {
    setState(() => _s = s);
    widget.onChanged(s);
  }

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(color: kWhite, fontSize: 16);
    const caption = TextStyle(
      color: kGrey,
      fontSize: 13,
      fontWeight: FontWeight.w300,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Row(
              icon: Icons.image_outlined,
              title: 'Choose new card image',
              onTap: () =>
                  Navigator.of(context).pop(SettingsAction.changeImage),
            ),
            if (widget.canAdjust)
              _Row(
                icon: Icons.crop_outlined,
                title: 'Adjust current image',
                onTap: () =>
                    Navigator.of(context).pop(SettingsAction.adjustImage),
              ),
            const Divider(color: kHairline, height: 28),
            const Text('Close after', style: label),
            const SizedBox(height: 10),
            SegmentedButton<int>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                backgroundColor: kBlack,
                foregroundColor: kGrey,
                selectedBackgroundColor: kHairline,
                selectedForegroundColor: kWhite,
                side: const BorderSide(color: kHairline),
              ),
              segments: [
                for (final s in timeoutChoices)
                  ButtonSegment(
                    value: s,
                    label: Text(s < 60 ? '${s}s' : '${s ~/ 60} min'),
                  ),
              ],
              selected: {_s.timeoutSeconds},
              onSelectionChanged: (v) =>
                  _update(_s.copyWith(timeoutSeconds: v.first)),
            ),
            const Divider(color: kHairline, height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show over lock screen', style: label),
              subtitle: const Text(
                'Card appears before you unlock. Wallet still asks you to unlock to pay.',
                style: caption,
              ),
              activeThumbColor: kWhite,
              activeTrackColor: const Color(0xFF34C759),
              value: _s.showOnLockScreen,
              onChanged: (v) => _update(_s.copyWith(showOnLockScreen: v)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: kGrey),
      title: Text(title, style: const TextStyle(color: kWhite, fontSize: 16)),
      onTap: onTap,
    );
  }
}
