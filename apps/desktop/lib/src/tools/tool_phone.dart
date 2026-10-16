import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../mux/daemon_state.dart';
import '../terminal/local_sessions_provider.dart' show appL10nProvider;
import '../terminal/sidebar_workspaces.dart';
import 'tool_registry.dart';

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
            'ws': sidebar.workspace(tool.ws)?.displayName(l10n) ?? '',
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
    if (slot != null) {
      final proxy = container.read(toolPhoneProxyProvider);
      container.listen<Uint8List>(
        phoneToolsBodyProvider,
        (_, body) => proxy.serve(ToolCatalog.fromServeBody(body)),
        fireImmediately: true,
      );
      container.read(_toolSlotPlugProvider).slot = slot;
      slot.target = proxy;
    } else {
      // The background service holds the relay: the list goes there on each link whose service says
      // it has tools (`hello.caps`), at once and whenever it changes; an older one is never sent it.
      void push() {
        final link = container.read(daemonLinkProvider);
        if (link == null || !link.info.caps.contains('tools')) return;
        link.client.send(MuxType.toolServe, {
          'b': container.read(phoneToolsBodyProvider),
        });
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
