import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import 'model_ack_dialog.dart';

/// App settings dialog. All values are session-scoped (in-memory) except the
/// one-time model-change acknowledgement, which persists as a marker file.
class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(selectedModelProvider);
    final splitOnWord = ref.watch(splitOnWordProvider);
    final skipBack = ref.watch(skipBackSecondsProvider);
    final skipForward = ref.watch(skipForwardSecondsProvider);

    return AlertDialog(
      backgroundColor: mochaSurface0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Settings',
        style: TextStyle(color: mochaText, fontSize: 18),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SectionLabel('Whisper'),
            _SettingRow(
              label: 'Model',
              trailing: DropdownButton<String>(
                value: model,
                dropdownColor: mochaSurface1,
                style: const TextStyle(color: mochaText, fontSize: 13),
                underline: const SizedBox.shrink(),
                items: availableModels
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    requestModelChange(ref, context, v);
                  }
                },
              ),
            ),
            _SettingRow(
              label: 'Word-level timestamps',
              trailing: Switch(
                value: splitOnWord,
                onChanged: (v) =>
                    ref.read(splitOnWordProvider.notifier).state = v,
                activeTrackColor: mochaMauve,
                activeThumbColor: mochaBase,
              ),
            ),
            if (splitOnWord)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Changes segment boundaries and disables VAD.',
                    style: TextStyle(color: mochaOverlay0, fontSize: 12),
                  ),
                ),
              ),
            const Divider(color: mochaSurface1),
            _SectionLabel('Playback'),
            _SettingRow(
              label: 'Skip back',
              trailing: _DurationField(
                value: skipBack,
                min: 1,
                max: 120,
                onChanged: (v) =>
                    ref.read(skipBackSecondsProvider.notifier).state = v,
              ),
            ),
            _SettingRow(
              label: 'Skip forward',
              trailing: _DurationField(
                value: skipForward,
                min: 1,
                max: 120,
                onChanged: (v) =>
                    ref.read(skipForwardSecondsProvider.notifier).state = v,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: mochaMauve),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            color: mochaOverlay0,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final Widget trailing;

  const _SettingRow({required this.label, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: mochaSubtext1, fontSize: 14),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _DurationField extends StatefulWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _DurationField({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  State<_DurationField> createState() => _DurationFieldState();
}

class _DurationFieldState extends State<_DurationField> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
  }

  @override
  void didUpdateWidget(covariant _DurationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync the field when the value changes from outside (e.g. a shortcut),
    // but only if the user isn't mid-edit.
    if (oldWidget.value != widget.value &&
        _controller.text != '${widget.value}') {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      setState(() => _errorText = 'Invalid');
      return;
    }
    final clamped = parsed.clamp(widget.min, widget.max);
    setState(() {
      _controller.text = '$clamped';
      _errorText = null;
    });
    if (clamped != widget.value) widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.right,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(color: mochaText, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          suffixText: 's',
          suffixStyle: const TextStyle(color: mochaSubtext0, fontSize: 13),
          errorText: _errorText,
          errorStyle: const TextStyle(fontSize: 10),
          filled: true,
          fillColor: mochaSurface1,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: (_) {
          _commit();
          FocusScope.of(context).unfocus();
        },
        onEditingComplete: _commit,
      ),
    );
  }
}
