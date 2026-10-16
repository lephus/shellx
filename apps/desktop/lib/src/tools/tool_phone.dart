import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../mux/daemon_state.dart';
import '../terminal/local_sessions_provider.dart' show appL10nProvider;
import '../terminal/sidebar_workspaces.dart';
import 'tool_registry.dart';

/// The most UTF-16 code units of a served tool's workspace name: `ServedTool.fromJson` drops an
/// entry with a longer `ws`, and a workspace name (64 characters) can be longer.
const int _kServedWsUnits = 200;

/// [name] in at most [_kServedWsUnits] UTF-16 code units, cut on a code point (never inside a
/// surrogate pair).
String _servedWs(String name) {
  if (name.length <= _kServedWsUnits) return name;
  var end = _kServedWsUnits;
  final last = name.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) {
    end--; // a lead surrogate: its pair stays out
  }
  return name.substring(0, end);
}

/// V2-4 E5: what phones may open, as the window says it (`tool.serve`'s `b`, or the in-process
/// proxy's list): every tool with its phone flag on and allowed (V2-3 D15, `phoneOn`) with its
/// workspace's name, and the ids of the other tools (a stream of one of them ends `disabled`, not
/// `gone`).
final phoneToolsBodyProvider = Provider<Uint8List>((ref) {
  final tools = ref.watch(toolRegistryProvider);
  final sidebar = ref.watch(sidebarWorkspacesProvider);
  final l10n = ref.watch(appL10nProvider);
  return ToolCatalog.serveBody(
    [
      for (final tool in tools)
        if (tool.phoneOn)
          {
            'id': tool.id,
            'name': tool.name,
            'ws': _servedWs(
              sidebar.workspace(tool.ws)?.displayName(l10n) ?? '',
            ),
            'group': tool.ws,
            'url': tool.url,
          },
    ],
    off: [
      for (final tool in tools)
        if (!tool.phoneOn) tool.id,
    ],
  );
});

/// V2-4 E5, in-process: the window holds the relay, so it hosts the tool proxy (one per run).
final toolPhoneProxyProvider = Provider<ToolProxy>((ref) {
  final proxy = ToolProxy();
  ref.onDispose(proxy.close);
  return proxy;
});

/// The slot the in-process proxy serves phones through (for [stopToolPhone]).
final class _ToolSlotPlug {
  ToolEndpointSlot? slot;
}

final _toolSlotPlugProvider = Provider<_ToolSlotPlug>((ref) => _ToolSlotPlug());

/// Called once by `main.dart` before any phone can reach the window: in-process the proxy becomes the
/// target of the agent side's [slot] (every runtime's router sends it `tool.*`) and serves the
/// window's list from now on; with the background service the list goes there instead. Never throws:
/// the window starts whatever happens here (phones then see no Tool group); the error's type goes to
/// the log.
void startToolPhone(ProviderContainer container, {ToolEndpointSlot? slot}) {
  try {
    // The list is rebuilt on every shell event: only one whose bytes changed is served or sent.
    if (slot != null) {
      final proxy = container.read(toolPhoneProxyProvider);
      Uint8List? served;
      container.listen<Uint8List>(phoneToolsBodyProvider, (_, body) {
        if (served != null && listEquals(served, body)) return;
        served = body;
        proxy.serve(ToolCatalog.fromServeBody(body));
      }, fireImmediately: true);
      container.read(_toolSlotPlugProvider).slot = slot;
      slot.target = proxy;
    } else {
      // The background service holds the relay: the list goes there on each link whose service says
      // it has tools (`hello.caps`), at once and whenever it changes; an older one is never sent it.
      // A new link always gets it.
      DaemonLink? pushedTo;
      Uint8List? pushed;
      void push() {
        final link = container.read(daemonLinkProvider);
        if (link == null || !link.info.caps.contains('tools')) return;
        final body = container.read(phoneToolsBodyProvider);
        if (identical(link, pushedTo) &&
            pushed != null &&
            listEquals(pushed, body)) {
          return;
        }
        pushedTo = link;
        pushed = body;
        link.client.send(MuxType.toolServe, {'b': body});
      }

      container.listen(daemonLinkProvider, (_, _) => push());
      container.listen<Uint8List>(
        phoneToolsBodyProvider,
        (_, _) => push(),
        fireImmediately: true,
      );
    }
  } on Object catch (error) {
    debugPrint(
      'ShellX: tools for phones failed to start: ${error.runtimeType}',
    );
  }
}

/// The window quits (V2-4 E5): in-process every phone stream ends `desktop_closed`, phones that list
/// hear `available: false`, and the slot stops serving. With the background service nothing changes:
/// it keeps the last list. Never throws.
void stopToolPhone(ProviderContainer container) {
  try {
    if (!container.exists(toolPhoneProxyProvider)) return;
    final proxy = container.read(toolPhoneProxyProvider);
    proxy.close();
    final slot = container.read(_toolSlotPlugProvider).slot;
    if (slot != null && identical(slot.target, proxy)) slot.target = null;
  } on Object catch (error) {
    debugPrint('ShellX: closing tools for phones failed: ${error.runtimeType}');
  }
}
