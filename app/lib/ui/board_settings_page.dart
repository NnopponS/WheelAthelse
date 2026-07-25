import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/state/board_settings_providers.dart';
import 'package:wheelathlete/theme/theme.dart';

/// Board Settings screen: edit board name, wheel side (L/R), and sample
/// rate (50/100/200 Hz) via the Config char + SET_NAME/SET_WHEEL/SET_RATE
/// commands.
///
/// Loads current values from the Config characteristic on init. The Save
/// button writes all three commands to the board.
class BoardSettingsPage extends ConsumerStatefulWidget {
  const BoardSettingsPage({super.key, required this.side});

  final WheelSide side;

  @override
  ConsumerState<BoardSettingsPage> createState() => _BoardSettingsPageState();
}

class _BoardSettingsPageState extends ConsumerState<BoardSettingsPage> {
  late TextEditingController _nameController;
  int? _wheelByte;
  int? _rateHz;
  bool _beepEnabled = true;
  bool _initialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _syncFromConfig(
    String name,
    int wheelByte,
    int rateHz,
    bool beepEnabled,
  ) {
    if (!_initialized) {
      _nameController = TextEditingController(text: name);
      _wheelByte = wheelByte;
      _rateHz = rateHz;
      _beepEnabled = beepEnabled;
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(boardSettingsProvider(widget.side));

    // Sync form fields when config loads.
    if (settings.config != null && !_initialized) {
      _syncFromConfig(
        settings.config!.name,
        settings.config!.wheelId.byte,
        settings.config!.rateHz,
        settings.config!.beepEnabled,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('${widget.side.label} Board Settings')),
      body: switch (settings.status) {
        BoardSettingsStatus.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        BoardSettingsStatus.error => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48),
              const SizedBox(height: AppSpacing.md),
              Text(settings.error ?? 'Unknown error'),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () =>
                    ref.invalidate(boardSettingsProvider(widget.side)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        BoardSettingsStatus.loaded ||
        BoardSettingsStatus.saving ||
        BoardSettingsStatus.saved => _buildForm(context, theme, settings),
      },
    );
  }

  Widget _buildForm(
    BuildContext context,
    ThemeData theme,
    BoardSettingsState settings,
  ) {
    if (!_initialized) {
      // Config loaded but fields not yet synced (shouldn't happen, but guard).
      return const Center(child: CircularProgressIndicator());
    }
    final saving = settings.status == BoardSettingsStatus.saving;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Board Name ──────────────────────────────────────────────
          Text('Board Name', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _nameController,
            maxLength: 24,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'e.g. WheelAthlete-L',
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Wheel Side ──────────────────────────────────────────────
          Text('Wheel Side', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0x4C,
                label: Text('Left (L)'),
                icon: Icon(Icons.arrow_back_rounded),
              ),
              ButtonSegment(
                value: 0x52,
                label: Text('Right (R)'),
                icon: Icon(Icons.arrow_forward_rounded),
              ),
            ],
            selected: _wheelByte != null ? {_wheelByte!} : const {},
            onSelectionChanged: (selection) {
              setState(() => _wheelByte = selection.first);
            },
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Sample Rate ─────────────────────────────────────────────
          Text('Sample Rate', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          DropdownButton<int>(
            value: _rateHz,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 50, child: Text('50 Hz')),
              DropdownMenuItem(value: 100, child: Text('100 Hz')),
              DropdownMenuItem(value: 200, child: Text('200 Hz')),
            ],
            onChanged: (v) => setState(() => _rateHz = v),
          ),
          const SizedBox(height: AppSpacing.xl),

          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _beepEnabled,
            onChanged: saving
                ? null
                : (value) => setState(() => _beepEnabled = value),
            secondary: const Icon(Icons.volume_up_rounded),
            title: const Text('Countdown sound'),
            subtitle: const Text(
              'Play countdown audio on supported boards and on the phone. '
              'The visual countdown remains active when sound is off.',
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── Firmware version (read-only) ────────────────────────────
          if (settings.config != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(
                      Icons.memory_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Firmware: ${settings.config!.fwVersion}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // ── Success banner (shown after save, keeps Save button visible) ──
          if (settings.status == BoardSettingsStatus.saved) ...[
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const Expanded(child: Text('Settings saved to board')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Save button ─────────────────────────────────────────────
          FilledButton.icon(
            onPressed:
                saving ||
                    _nameController.text.isEmpty ||
                    _wheelByte == null ||
                    _rateHz == null
                ? null
                : () => _save(),
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(saving ? 'Saving…' : 'Save to Board'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final notifier = ref.read(boardSettingsProvider(widget.side).notifier);
    await notifier.save(
      name: _nameController.text,
      wheelByte: _wheelByte!,
      rateHz: _rateHz!,
      beepEnabled: _beepEnabled,
    );
  }
}
