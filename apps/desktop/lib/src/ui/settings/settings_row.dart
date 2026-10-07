import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../../agent/notify_threshold.dart';
import '../../config/config_color.dart';
import '../../config/config_controller.dart';
import '../../config/config_problem.dart';
import '../../config/settings_schema.dart';
import '../../terminal/terminal_font_size.dart';
import '../../tray/tray_action.dart';
import '../../tray/tray_actions.dart';
import '../../tray/tray_menu.dart' show notifyThresholdLabel;
import '../config/action_labels.dart' show problemText;
import '../theme/shellx_desktop_theme.dart';
import 'settings_values.dart';
import 'settings_writer.dart';

/// How long a slider waits after the last keyboard step before it writes
/// (A11 limits: settings write debounce 300 ms; a drag writes on release).
const Duration kSettingWriteDebounce = Duration(milliseconds: 300);

/// A hook the Appearance page uses to show a value in the sample before it
/// is written: [raw] is the value being tried, or null when a write has
/// finished (written or not) and the sample goes back to the saved values.
typedef SettingPreviewHook = void Function(SettingDef def, String? raw);

/// What a page-specific control (the theme list) gets from its row: whether
/// it may be used, the value the file has, and how to write one.
class SettingControlApi {
  const SettingControlApi({
    required this.editable,
    required this.current,
    required this.commit,
  });
  final bool editable;
  final String current;
  final Future<void> Function(String raw) commit;
}

typedef SettingControlBuilder =
    Widget Function(BuildContext context, SettingControlApi api);

/// What every row of the window shares: where "Open configuration file" goes
/// and which row a search jump lights up for a second.
class SettingsScope extends InheritedWidget {
  const SettingsScope({
    super.key,
    required this.onOpenFile,
    required this.highlightId,
    required super.child,
  });
  final VoidCallback onOpenFile;
  final String? highlightId;

  static SettingsScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()!;

  @override
  bool updateShouldNotify(SettingsScope old) =>
      old.highlightId != highlightId || old.onOpenFile != onOpenFile;
}

/// One row of the Settings window (A11 D4, UI §4.1): label, control, the
/// "Saved in the configuration file" line, the error of the last attempt
/// and, for a value that cannot be edited here, why.
///
/// A file row reads [ConfigState] and writes through [SettingsWriter] only
/// on a gesture of the user; an app row calls the tray's own
/// `TrayActions.handle`.
class SettingRow extends ConsumerStatefulWidget {
  const SettingRow({
    super.key,
    required this.def,
    this.pageCaption,
    this.onJump,
    this.note,
    this.onPreview,
    this.control,
    this.enabled = true,
  });

  final SettingDef def;

  /// False: the row is shown but cannot be used (Phone, signed out).
  final bool enabled;

  /// A search hit: the name of the page, a link that opens it.
  final String? pageCaption;
  final VoidCallback? onJump;

  /// A line under the control (`settingsScrollbackNote`).
  final String? note;
  final SettingPreviewHook? onPreview;

  /// Replaces the standard control of a file row (Appearance: the theme
  /// list); the row keeps everything around it.
  final SettingControlBuilder? control;

  @override
  ConsumerState<SettingRow> createState() => _SettingRowState();
}

class _SettingRowState extends ConsumerState<SettingRow> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  String? _error;
  double? _dragValue;

  /// A pointer is on the slider (a drag): it writes on release. Keys and
  /// assistive actions also start and end a "drag", so they are told apart
  /// by the pointer, and write 300 ms after the last step.
  bool _pointerDown = false;
  Timer? _debounce;
  String? _pending;

  /// What the last commit tried to write: Enter commits and then the field
  /// loses the focus, which must not write the same thing a second time
  /// (nor retry one the file refused).
  String? _attempted;
  // Kept in a field: `ref` can't be read while the widget is taken apart.
  late final SettingsWriter _writer;

  SettingDef get def => widget.def;
  bool get _isFile => def.owner == SettingOwner.file;

  @override
  void initState() {
    super.initState();
    _writer = ref.read(settingsWriterProvider);
    _focus.addListener(_onFocus);
    if (_isFile) {
      _field.text = _currentText();
      // A reload (a hand edit, another row's write): a field the user is not
      // typing in follows the file.
      ref.listenManual(shellxConfigProvider.select((s) => s.generation), (
        _,
        _,
      ) {
        if (!mounted || _focus.hasFocus) return;
        final text = fileSettingText(
          def,
          ref.read(shellxConfigProvider).config,
        );
        if (_field.text != text) _field.text = text;
        if (_error != null) setState(() => _error = null);
        setState(() => _dragValue = null);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // A keyboard step still waiting for its write is the user's: keep it.
    final pending = _pending;
    if (pending != null && _isFile) unawaited(_writer.set(def, pending));
    _focus.dispose();
    _field.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus && _isFile) {
      unawaited(_commit(_field.text, fromBlur: true));
    }
  }

  String _currentText() => fileSettingText(
    def,
    ref.read(shellxConfigProvider).config,
    liveFontSize: ref.read(terminalFontSizeProvider),
  );

  String get _current => _currentText();

  /// Writes [raw] (a gesture committed it) and shows what came of it.
  Future<void> _commit(String raw, {bool fromBlur = false}) async {
    _debounce?.cancel();
    _pending = null;
    if (raw.trim() == _current) {
      _attempted = null;
      widget.onPreview?.call(def, null); // nothing to show but the saved value
      if (_error != null) setState(() => _error = null);
      return;
    }
    if (fromBlur && raw.trim() == _attempted) return;
    _attempted = raw.trim();
    final result = await _writer.set(def, raw);
    if (!mounted) return;
    reportWrite(ref, result);
    // Written or refused, the sample goes back to the saved configuration.
    widget.onPreview?.call(def, null);
    setState(() {
      _error = result is Invalid
          ? problemText(AppLocalizations.of(context), result.problem)
          : null;
      if (result is! Saved) _dragValue = null;
    });
  }

  void _commitField() => unawaited(_commit(_field.text));

  Future<void> _reset() async {
    final result = await _writer.reset(def);
    if (!mounted) return;
    reportWrite(ref, result);
    setState(() => _error = null);
  }

  void _handle(TrayAction action) =>
      unawaited(ref.read(trayActionsProvider).handle(action));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = settingLabel(def, l10n);
    final scope = SettingsScope.of(context);
    final SettingSource? source;
    if (_isFile) {
      source = settingSource(
        def,
        ref.watch(shellxConfigProvider),
        ref.watch(configPathsProvider),
        ownBlock: ref.watch(settingsOwnBlockProvider).value,
      );
    } else {
      source = null;
    }
    // What only the window can find (the font probe), after a load.
    final warnings = _isFile
        ? [
            for (final p in ref.watch(
              shellxConfigProvider.select((s) => s.runtimeProblems),
            ))
              if (p.key == def.fileKey && p.severity == ConfigSeverity.warning)
                p,
          ]
        : const <ConfigProblem>[];
    final editable =
        widget.enabled &&
        source is! IncludeSource &&
        source is! MultiLineSource;
    final inline = def.control == SettingControl.toggle;
    final control = _isFile
        ? _fileControl(l10n, label, editable)
        : _appControl(l10n, label);
    final canReset =
        _isFile &&
        (source is OwnSource ||
            source is UserLineSource ||
            source is GhosttySource);

    final head = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _labelBlock(l10n, label)),
        if (inline) ...[const SizedBox(width: 12), control],
      ],
    );
    return Container(
      key: Key('setting.${def.id}'),
      decoration: BoxDecoration(
        color: (scope.highlightId == def.id)
            ? ShellxDesktopColors.primarySoft
            : Colors.transparent,
        borderRadius: BorderRadius.circular(ShellxRadius.r6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head,
          if (!inline) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: control),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  key: Key('setting.${def.id}.error'),
                  style: ShellxText.small.copyWith(
                    color: ShellxDesktopColors.err,
                  ),
                ),
              ),
            ),
          for (final problem in warnings)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  problemText(l10n, problem),
                  key: Key('setting.${def.id}.warning'),
                  style: ShellxText.small.copyWith(
                    color: ShellxDesktopColors.warn,
                  ),
                ),
              ),
            ),
          if (widget.note != null) _caption(widget.note!),
          if (source != null) ..._sourceLines(l10n, source, scope),
          if (_isFile || canReset)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  if (_isFile) _caption(l10n.settingsSavedInFile(def.fileKey!)),
                  if (canReset)
                    TextButton(
                      key: Key('setting.${def.id}.reset'),
                      onPressed: _reset,
                      child: Text(l10n.settingsReset),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _caption(String text) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(
      text,
      style: ShellxText.small.copyWith(
        color: ShellxDesktopColors.textSecondary,
      ),
    ),
  );

  Widget _labelBlock(AppLocalizations l10n, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.pageCaption != null)
        InkWell(
          onTap: widget.onJump,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              widget.pageCaption!,
              style: ShellxText.caption.copyWith(
                color: ShellxDesktopColors.accent,
              ),
            ),
          ),
        ),
      Text(
        label,
        style: ShellxText.body.copyWith(color: ShellxDesktopColors.textPrimary),
      ),
      if (def.description != null) _caption(def.description!(l10n)),
    ],
  );

  List<Widget> _sourceLines(
    AppLocalizations l10n,
    SettingSource source,
    SettingsScope scope,
  ) {
    final text = switch (source) {
      IncludeSource(:final file, :final line) => l10n.settingsSetIn(
        p.basename(file),
        line,
      ),
      MultiLineSource() => l10n.settingsMultiLine,
      GhosttySource() => l10n.settingsFromGhostty,
      _ => null,
    };
    if (text == null) return const [];
    final readOnly = source is IncludeSource || source is MultiLineSource;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              text,
              key: Key('setting.${def.id}.source'),
              style: ShellxText.small.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
            if (readOnly)
              TextButton(
                key: Key('setting.${def.id}.open-file'),
                onPressed: scope.onOpenFile,
                child: Text(l10n.settingsOpenFile),
              ),
          ],
        ),
      ),
    ];
  }

  // ---- app switches ---------------------------------------------------

  Widget _appControl(AppLocalizations l10n, String label) {
    final agent = ref.watch(agentControllerProvider);
    final local = ref.watch(trayLocalStateProvider);
    if (def.control == SettingControl.choice) {
      // The long-command threshold: one choice per `SetNotifyThreshold`.
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final seconds in kNotifyThresholdChoices)
            ChoiceChip(
              key: Key('setting.${def.id}.opt.$seconds'),
              label: Text(notifyThresholdLabel(seconds, l10n)),
              selected: agent.notifyThresholdSeconds == seconds,
              onSelected: widget.enabled
                  ? (_) => _handle(SetNotifyThreshold(seconds))
                  : null,
            ),
        ],
      );
    }
    final enabled =
        widget.enabled &&
        (def.id != 'desktop-notifications-only-unfocused' ||
            agent.desktopNotifications);
    return Semantics(
      label: label,
      child: Switch(
        key: Key('setting.${def.id}.switch'),
        value: appSwitchValue(def, agent, local),
        onChanged: enabled ? (_) => _handle(def.toggle!) : null,
      ),
    );
  }

  // ---- file keys ------------------------------------------------------

  Widget _fileControl(AppLocalizations l10n, String label, bool editable) {
    final config = ref.watch(shellxConfigProvider).config;
    final custom = widget.control;
    if (custom != null) {
      return custom(
        context,
        SettingControlApi(
          editable: editable,
          current: fileSettingText(
            def,
            config,
            liveFontSize: ref.watch(terminalFontSizeProvider),
          ),
          commit: _commit,
        ),
      );
    }
    final text = fileSettingText(
      def,
      config,
      liveFontSize: ref.watch(terminalFontSizeProvider),
    );
    switch (def.control) {
      case SettingControl.toggle:
        return Semantics(
          label: label,
          child: Switch(
            key: Key('setting.${def.id}.switch'),
            value: text == 'true',
            onChanged: editable ? (v) => _commit('$v') : null,
          ),
        );
      case SettingControl.segmented || SettingControl.choice
          when def.choices != null || def.id == 'macos-option-as-alt':
        return _choices(l10n, text, editable);
      case SettingControl.slider:
        return _slider(l10n, label, text, editable);
      case SettingControl.color:
        return _textField(
          l10n,
          label,
          editable,
          hint: l10n.settingsHexHint,
          swatch: true,
        );
      case SettingControl.path:
        return _workingDir(l10n, label, text, editable);
      default:
        return _textField(
          l10n,
          label,
          editable,
          hint: def.fileKey == 'font-family'
              ? l10n.settingsFontFamilyHint
              : l10n.settingsDefaultValue,
        );
    }
  }

  List<SettingChoice> _choiceList(AppLocalizations l10n) {
    if (def.choices != null) return def.choices!;
    // macos-option-as-alt: four words, one per wire value.
    return [
      SettingChoice('false', (l) => l.settingsOptionAsAltOff),
      SettingChoice('left', (l) => l.settingsOptionAsAltLeft),
      SettingChoice('right', (l) => l.settingsOptionAsAltRight),
      SettingChoice('true', (l) => l.settingsOptionAsAltBoth),
    ];
  }

  Widget _choices(AppLocalizations l10n, String current, bool editable) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final choice in _choiceList(l10n))
          ChoiceChip(
            key: Key('setting.${def.id}.opt.${choice.wire}'),
            label: Text(choice.label(l10n)),
            selected: current == choice.wire,
            onSelected: editable
                ? (_) {
                    widget.onPreview?.call(def, choice.wire);
                    unawaited(_commit(choice.wire));
                  }
                : null,
          ),
      ],
    );
  }

  Widget _slider(
    AppLocalizations l10n,
    String label,
    String text,
    bool editable,
  ) {
    final min = def.min!, max = def.max!, step = def.step ?? 1;
    final shown = (_dragValue ?? double.tryParse(text) ?? min).clamp(min, max);
    final divisions = math.max(1, ((max - min) / step).round());
    String fmt(double v) =>
        v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 260,
          child: Listener(
            onPointerDown: (_) => _pointerDown = true,
            // After the slider's own release handler has run.
            onPointerUp: (_) => scheduleMicrotask(() => _pointerDown = false),
            onPointerCancel: (_) =>
                scheduleMicrotask(() => _pointerDown = false),
            child: Semantics(
              label: label,
              child: Slider(
                key: Key('setting.${def.id}.slider'),
                value: shown.toDouble(),
                min: min,
                max: max,
                divisions: divisions,
                label: fmt(shown.toDouble()),
                onChanged: editable
                    ? (v) {
                        setState(() => _dragValue = v);
                        _field.text = fmt(v);
                        widget.onPreview?.call(def, fmt(v));
                        if (!_pointerDown) {
                          // A keyboard step: write once the keys pause.
                          _pending = fmt(v);
                          _debounce?.cancel();
                          _debounce = Timer(kSettingWriteDebounce, () {
                            final raw = _pending;
                            if (raw != null) unawaited(_commit(raw));
                          });
                        }
                      }
                    : null,
                onChangeEnd: editable
                    ? (v) {
                        // A drag writes on release; a keyboard step was
                        // already scheduled by onChanged.
                        if (_pointerDown) unawaited(_commit(fmt(v)));
                      }
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 72, child: _plainField(label, editable, hint: '')),
      ],
    );
  }

  Widget _plainField(String label, bool editable, {required String hint}) {
    return Semantics(
      textField: true,
      label: label,
      child: TextField(
        key: Key('setting.${def.id}.field'),
        controller: _field,
        focusNode: _focus,
        enabled: editable,
        onChanged: (v) => widget.onPreview?.call(def, v),
        onSubmitted: (_) => _commitField(),
        decoration: InputDecoration(hintText: hint, isDense: true),
      ),
    );
  }

  Widget _textField(
    AppLocalizations l10n,
    String label,
    bool editable, {
    required String hint,
    bool swatch = false,
  }) {
    final color = swatch ? parseConfigColor(_field.text) : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (swatch)
          ExcludeSemantics(
            child: Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: color ?? Colors.transparent,
                borderRadius: BorderRadius.circular(ShellxRadius.r4),
                border: Border.all(color: ShellxDesktopColors.borderInput),
              ),
            ),
          ),
        SizedBox(
          width: 280,
          child: Semantics(
            textField: true,
            label: label,
            child: TextField(
              key: Key('setting.${def.id}.field'),
              controller: _field,
              focusNode: _focus,
              enabled: editable,
              onChanged: (_) => swatch ? setState(() {}) : null,
              onSubmitted: (_) => _commitField(),
              decoration: InputDecoration(hintText: hint, isDense: true),
            ),
          ),
        ),
      ],
    );
  }

  Widget _workingDir(
    AppLocalizations l10n,
    String label,
    String text,
    bool editable,
  ) {
    final kind = text == 'home' || text == 'inherit' ? text : 'path';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final (wire, name) in [
              ('home', l10n.settingsWorkingDirHome),
              ('inherit', l10n.settingsWorkingDirInherit),
              ('path', l10n.settingsWorkingDirPath),
            ])
              ChoiceChip(
                key: Key('setting.${def.id}.opt.$wire'),
                label: Text(name),
                selected: kind == wire,
                onSelected: editable
                    ? (_) {
                        if (wire == 'path') {
                          setState(() => _field.text = '');
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _focus.requestFocus(),
                          );
                        } else {
                          _field.text = wire;
                          unawaited(_commit(wire));
                        }
                      }
                    : null,
              ),
          ],
        ),
        if (kind == 'path' || _field.text.isEmpty && !_isKeyword(_field.text))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _textField(l10n, label, editable, hint: '/'),
          ),
      ],
    );
  }

  static bool _isKeyword(String v) => v == 'home' || v == 'inherit';
}
