// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:auto_route/auto_route.dart' as _i12;
import 'package:flutter/foundation.dart' as _i14;
import 'package:shellx_client/shellx_client.dart' as _i15;
import 'package:shellx_mobile/core/core.dart' as _i13;
import 'package:shellx_mobile/features/ai/presentation/pages/ai_session_page.dart'
    as _i1;
import 'package:shellx_mobile/features/app/splash_page.dart' as _i8;
import 'package:shellx_mobile/features/app/update_required_page.dart' as _i11;
import 'package:shellx_mobile/features/auth/presentation/pages/login_page.dart'
    as _i3;
import 'package:shellx_mobile/features/auth/presentation/pages/register_page.dart'
    as _i6;
import 'package:shellx_mobile/features/machines/presentation/pages/machine_list_page.dart'
    as _i4;
import 'package:shellx_mobile/features/pairing/presentation/pages/qr_scanner_page.dart'
    as _i5;
import 'package:shellx_mobile/features/settings/presentation/pages/delete_account_page.dart'
    as _i2;
import 'package:shellx_mobile/features/settings/presentation/pages/settings_page.dart'
    as _i7;
import 'package:shellx_mobile/features/terminal/presentation/pages/terminal_page.dart'
    as _i9;
import 'package:shellx_mobile/features/tools/presentation/pages/tool_page.dart'
    as _i10;

/// generated route for
/// [_i1.AiSessionPage]
class AiSessionRoute extends _i12.PageRouteInfo<AiSessionRouteArgs> {
  AiSessionRoute({
    _i13.Key? key,
    required String agentId,
    required String machineName,
    required String sid,
    List<_i12.PageRouteInfo>? children,
  }) : super(
         AiSessionRoute.name,
         args: AiSessionRouteArgs(
           key: key,
           agentId: agentId,
           machineName: machineName,
           sid: sid,
         ),
         initialChildren: children,
       );

  static const String name = 'AiSessionRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AiSessionRouteArgs>();
      return _i1.AiSessionPage(
        key: args.key,
        agentId: args.agentId,
        machineName: args.machineName,
        sid: args.sid,
      );
    },
  );
}

class AiSessionRouteArgs {
  const AiSessionRouteArgs({
    this.key,
    required this.agentId,
    required this.machineName,
    required this.sid,
  });

  final _i13.Key? key;

  final String agentId;

  final String machineName;

  final String sid;

  @override
  String toString() {
    return 'AiSessionRouteArgs{key: $key, agentId: $agentId, machineName: $machineName, sid: $sid}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AiSessionRouteArgs) return false;
    return key == other.key &&
        agentId == other.agentId &&
        machineName == other.machineName &&
        sid == other.sid;
  }

  @override
  int get hashCode =>
      key.hashCode ^ agentId.hashCode ^ machineName.hashCode ^ sid.hashCode;
}

/// generated route for
/// [_i2.DeleteAccountPage]
class DeleteAccountRoute extends _i12.PageRouteInfo<void> {
  const DeleteAccountRoute({List<_i12.PageRouteInfo>? children})
    : super(DeleteAccountRoute.name, initialChildren: children);

  static const String name = 'DeleteAccountRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i2.DeleteAccountPage();
    },
  );
}

/// generated route for
/// [_i3.LoginPage]
class LoginRoute extends _i12.PageRouteInfo<void> {
  const LoginRoute({List<_i12.PageRouteInfo>? children})
    : super(LoginRoute.name, initialChildren: children);

  static const String name = 'LoginRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i3.LoginPage();
    },
  );
}

/// generated route for
/// [_i4.MachineListPage]
class MachineListRoute extends _i12.PageRouteInfo<void> {
  const MachineListRoute({List<_i12.PageRouteInfo>? children})
    : super(MachineListRoute.name, initialChildren: children);

  static const String name = 'MachineListRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i4.MachineListPage();
    },
  );
}

/// generated route for
/// [_i5.QrScannerPage]
class QrScannerRoute extends _i12.PageRouteInfo<QrScannerRouteArgs> {
  QrScannerRoute({
    _i13.Key? key,
    _i5.ScannerViewBuilder scannerBuilder = _i5.cameraScannerView,
    List<_i12.PageRouteInfo>? children,
  }) : super(
         QrScannerRoute.name,
         args: QrScannerRouteArgs(key: key, scannerBuilder: scannerBuilder),
         initialChildren: children,
       );

  static const String name = 'QrScannerRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<QrScannerRouteArgs>(
        orElse: () => const QrScannerRouteArgs(),
      );
      return _i5.QrScannerPage(
        key: args.key,
        scannerBuilder: args.scannerBuilder,
      );
    },
  );
}

class QrScannerRouteArgs {
  const QrScannerRouteArgs({
    this.key,
    this.scannerBuilder = _i5.cameraScannerView,
  });

  final _i13.Key? key;

  final _i5.ScannerViewBuilder scannerBuilder;

  @override
  String toString() {
    return 'QrScannerRouteArgs{key: $key, scannerBuilder: $scannerBuilder}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! QrScannerRouteArgs) return false;
    return key == other.key && scannerBuilder == other.scannerBuilder;
  }

  @override
  int get hashCode => key.hashCode ^ scannerBuilder.hashCode;
}

/// generated route for
/// [_i6.RegisterPage]
class RegisterRoute extends _i12.PageRouteInfo<void> {
  const RegisterRoute({List<_i12.PageRouteInfo>? children})
    : super(RegisterRoute.name, initialChildren: children);

  static const String name = 'RegisterRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i6.RegisterPage();
    },
  );
}

/// generated route for
/// [_i7.SettingsPage]
class SettingsRoute extends _i12.PageRouteInfo<void> {
  const SettingsRoute({List<_i12.PageRouteInfo>? children})
    : super(SettingsRoute.name, initialChildren: children);

  static const String name = 'SettingsRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i7.SettingsPage();
    },
  );
}

/// generated route for
/// [_i8.SplashPage]
class SplashRoute extends _i12.PageRouteInfo<void> {
  const SplashRoute({List<_i12.PageRouteInfo>? children})
    : super(SplashRoute.name, initialChildren: children);

  static const String name = 'SplashRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i8.SplashPage();
    },
  );
}

/// generated route for
/// [_i9.TerminalPage]
class TerminalRoute extends _i12.PageRouteInfo<TerminalRouteArgs> {
  TerminalRoute({
    _i14.Key? key,
    required String agentId,
    required String machineName,
    List<_i12.PageRouteInfo>? children,
  }) : super(
         TerminalRoute.name,
         args: TerminalRouteArgs(
           key: key,
           agentId: agentId,
           machineName: machineName,
         ),
         initialChildren: children,
       );

  static const String name = 'TerminalRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<TerminalRouteArgs>();
      return _i9.TerminalPage(
        key: args.key,
        agentId: args.agentId,
        machineName: args.machineName,
      );
    },
  );
}

class TerminalRouteArgs {
  const TerminalRouteArgs({
    this.key,
    required this.agentId,
    required this.machineName,
  });

  final _i14.Key? key;

  final String agentId;

  final String machineName;

  @override
  String toString() {
    return 'TerminalRouteArgs{key: $key, agentId: $agentId, machineName: $machineName}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TerminalRouteArgs) return false;
    return key == other.key &&
        agentId == other.agentId &&
        machineName == other.machineName;
  }

  @override
  int get hashCode => key.hashCode ^ agentId.hashCode ^ machineName.hashCode;
}

/// generated route for
/// [_i10.ToolPage]
class ToolRoute extends _i12.PageRouteInfo<ToolRouteArgs> {
  ToolRoute({
    _i13.Key? key,
    required String agentId,
    required _i15.ToolInfo tool,
    List<_i12.PageRouteInfo>? children,
  }) : super(
         ToolRoute.name,
         args: ToolRouteArgs(key: key, agentId: agentId, tool: tool),
         initialChildren: children,
       );

  static const String name = 'ToolRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ToolRouteArgs>();
      return _i10.ToolPage(
        key: args.key,
        agentId: args.agentId,
        tool: args.tool,
      );
    },
  );
}

class ToolRouteArgs {
  const ToolRouteArgs({this.key, required this.agentId, required this.tool});

  final _i13.Key? key;

  final String agentId;

  final _i15.ToolInfo tool;

  @override
  String toString() {
    return 'ToolRouteArgs{key: $key, agentId: $agentId, tool: $tool}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ToolRouteArgs) return false;
    return key == other.key && agentId == other.agentId && tool == other.tool;
  }

  @override
  int get hashCode => key.hashCode ^ agentId.hashCode ^ tool.hashCode;
}

/// generated route for
/// [_i11.UpdateRequiredPage]
class UpdateRequiredRoute extends _i12.PageRouteInfo<void> {
  const UpdateRequiredRoute({List<_i12.PageRouteInfo>? children})
    : super(UpdateRequiredRoute.name, initialChildren: children);

  static const String name = 'UpdateRequiredRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i11.UpdateRequiredPage();
    },
  );
}
