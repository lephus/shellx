// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:auto_route/auto_route.dart' as _i14;
import 'package:flutter/foundation.dart' as _i17;
import 'package:shellx_client/shellx_client.dart' as _i18;
import 'package:shellx_mobile/core/core.dart' as _i15;
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart'
    as _i16;
import 'package:shellx_mobile/features/ai/presentation/pages/ai_file_diff_page.dart'
    as _i1;
import 'package:shellx_mobile/features/ai/presentation/pages/ai_item_page.dart'
    as _i2;
import 'package:shellx_mobile/features/ai/presentation/pages/ai_session_page.dart'
    as _i3;
import 'package:shellx_mobile/features/app/splash_page.dart' as _i10;
import 'package:shellx_mobile/features/app/update_required_page.dart' as _i13;
import 'package:shellx_mobile/features/auth/presentation/pages/login_page.dart'
    as _i5;
import 'package:shellx_mobile/features/auth/presentation/pages/register_page.dart'
    as _i8;
import 'package:shellx_mobile/features/machines/presentation/pages/machine_list_page.dart'
    as _i6;
import 'package:shellx_mobile/features/pairing/presentation/pages/qr_scanner_page.dart'
    as _i7;
import 'package:shellx_mobile/features/settings/presentation/pages/delete_account_page.dart'
    as _i4;
import 'package:shellx_mobile/features/settings/presentation/pages/settings_page.dart'
    as _i9;
import 'package:shellx_mobile/features/terminal/presentation/pages/terminal_page.dart'
    as _i11;
import 'package:shellx_mobile/features/tools/presentation/pages/tool_page.dart'
    as _i12;

/// generated route for
/// [_i1.AiFileDiffPage]
class AiFileDiffRoute extends _i14.PageRouteInfo<AiFileDiffRouteArgs> {
  AiFileDiffRoute({
    _i15.Key? key,
    required _i16.AiSessionController controller,
    required String path,
    int? turn,
    List<_i14.PageRouteInfo>? children,
  }) : super(
         AiFileDiffRoute.name,
         args: AiFileDiffRouteArgs(
           key: key,
           controller: controller,
           path: path,
           turn: turn,
         ),
         initialChildren: children,
       );

  static const String name = 'AiFileDiffRoute';

  static _i14.PageInfo page = _i14.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AiFileDiffRouteArgs>();
      return _i1.AiFileDiffPage(
        key: args.key,
        controller: args.controller,
        path: args.path,
        turn: args.turn,
      );
    },
  );
}

class AiFileDiffRouteArgs {
  const AiFileDiffRouteArgs({
    this.key,
    required this.controller,
    required this.path,
    this.turn,
  });

  final _i15.Key? key;

  final _i16.AiSessionController controller;

  final String path;

  final int? turn;

  @override
  String toString() {
    return 'AiFileDiffRouteArgs{key: $key, controller: $controller, path: $path, turn: $turn}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AiFileDiffRouteArgs) return false;
    return key == other.key &&
        controller == other.controller &&
        path == other.path &&
        turn == other.turn;
  }

  @override
  int get hashCode =>
      key.hashCode ^ controller.hashCode ^ path.hashCode ^ turn.hashCode;
}

/// generated route for
/// [_i2.AiItemPage]
class AiItemRoute extends _i14.PageRouteInfo<AiItemRouteArgs> {
  AiItemRoute({
    _i15.Key? key,
    required String title,
    required _i2.AiFullLoader load,
    List<_i14.PageRouteInfo>? children,
  }) : super(
         AiItemRoute.name,
         args: AiItemRouteArgs(key: key, title: title, load: load),
         initialChildren: children,
       );

  static const String name = 'AiItemRoute';

  static _i14.PageInfo page = _i14.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AiItemRouteArgs>();
      return _i2.AiItemPage(key: args.key, title: args.title, load: args.load);
    },
  );
}

class AiItemRouteArgs {
  const AiItemRouteArgs({this.key, required this.title, required this.load});

  final _i15.Key? key;

  final String title;

  final _i2.AiFullLoader load;

  @override
  String toString() {
    return 'AiItemRouteArgs{key: $key, title: $title, load: $load}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AiItemRouteArgs) return false;
    return key == other.key && title == other.title && load == other.load;
  }

  @override
  int get hashCode => key.hashCode ^ title.hashCode ^ load.hashCode;
}

/// generated route for
/// [_i3.AiSessionPage]
class AiSessionRoute extends _i14.PageRouteInfo<AiSessionRouteArgs> {
  AiSessionRoute({
    _i17.Key? key,
    required String agentId,
    required String machineName,
    required String sid,
    List<_i14.PageRouteInfo>? children,
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

  static _i14.PageInfo page = _i14.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AiSessionRouteArgs>();
      return _i3.AiSessionPage(
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

  final _i17.Key? key;

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
/// [_i4.DeleteAccountPage]
class DeleteAccountRoute extends _i14.PageRouteInfo<void> {
  const DeleteAccountRoute({List<_i14.PageRouteInfo>? children})
    : super(DeleteAccountRoute.name, initialChildren: children);

  static const String name = 'DeleteAccountRoute';

  static _i14.PageInfo page = _i14.PageInfo(
    name,
    builder: (data) {
      return const _i4.DeleteAccountPage();
    },
  );
}

/// generated route for
/// [_i5.LoginPage]
class LoginRoute extends _i14.PageRouteInfo<void> {
  const LoginRoute({List<_i14.PageRouteInfo>? children})
    : super(LoginRoute.name, initialChildren: children);

  static const String name = 'LoginRoute';

  static _i14.PageInfo page = _i14.PageInfo(
    name,
    builder: (data) {
      return const _i5.LoginPage();
    },
  );
}

/// generated route for
/// [_i6.MachineListPage]
class MachineListRoute extends _i14.PageRouteInfo<void> {
  const MachineListRoute({List<_i14.PageRouteInfo>? children})
    : super(MachineListRoute.name, initialChildren: children);

  static const String name = 'MachineListRoute';

  static _i14.PageInfo page = _i14.PageInfo(
    name,
    builder: (data) {
      return const _i6.MachineListPage();
    },
  );
}

/// generated route for
/// [_i7.QrScannerPage]
class QrScannerRoute extends _i14.PageRouteInfo<QrScannerRouteArgs> {
  QrScannerRoute({
    _i15.Key? key,
    _i7.ScannerViewBuilder scannerBuilder = _i7.cameraScannerView,
    List<_i14.PageRouteInfo>? children,
  }) : super(
         QrScannerRoute.name,
         args: QrScannerRouteArgs(key: key, scannerBuilder: scannerBuilder),
         initialChildren: children,
       );

  static const String name = 'QrScannerRoute';

  static _i14.PageInfo page = _i14.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<QrScannerRouteArgs>(
        orElse: () => const QrScannerRouteArgs(),
      );
      return _i7.QrScannerPage(
        key: args.key,
        scannerBuilder: args.scannerBuilder,
      );
    },
  );
}

class QrScannerRouteArgs {
  const QrScannerRouteArgs({
    this.key,
    this.scannerBuilder = _i7.cameraScannerView,
  });

  final _i15.Key? key;

  final _i7.ScannerViewBuilder scannerBuilder;

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
/// [_i8.RegisterPage]
class RegisterRoute extends _i14.PageRouteInfo<void> {
  const RegisterRoute({List<_i14.PageRouteInfo>? children})
    : super(RegisterRoute.name, initialChildren: children);

  static const String name = 'RegisterRoute';

  static _i14.PageInfo page = _i14.PageInfo(
    name,
    builder: (data) {
      return const _i8.RegisterPage();
    },
  );
}

/// generated route for
/// [_i9.SettingsPage]
class SettingsRoute extends _i14.PageRouteInfo<void> {
  const SettingsRoute({List<_i14.PageRouteInfo>? children})
    : super(SettingsRoute.name, initialChildren: children);

  static const String name = 'SettingsRoute';

  static _i14.PageInfo page = _i14.PageInfo(
    name,
    builder: (data) {
      return const _i9.SettingsPage();
    },
  );
}

/// generated route for
/// [_i10.SplashPage]
class SplashRoute extends _i14.PageRouteInfo<void> {
  const SplashRoute({List<_i14.PageRouteInfo>? children})
    : super(SplashRoute.name, initialChildren: children);

  static const String name = 'SplashRoute';

  static _i14.PageInfo page = _i14.PageInfo(
    name,
    builder: (data) {
      return const _i10.SplashPage();
    },
  );
}

/// generated route for
/// [_i11.TerminalPage]
class TerminalRoute extends _i14.PageRouteInfo<TerminalRouteArgs> {
  TerminalRoute({
    _i17.Key? key,
    required String agentId,
    required String machineName,
    List<_i14.PageRouteInfo>? children,
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

  static _i14.PageInfo page = _i14.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<TerminalRouteArgs>();
      return _i11.TerminalPage(
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

  final _i17.Key? key;

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
/// [_i12.ToolPage]
class ToolRoute extends _i14.PageRouteInfo<ToolRouteArgs> {
  ToolRoute({
    _i15.Key? key,
    required String agentId,
    required _i18.ToolInfo tool,
    List<_i14.PageRouteInfo>? children,
  }) : super(
         ToolRoute.name,
         args: ToolRouteArgs(key: key, agentId: agentId, tool: tool),
         initialChildren: children,
       );

  static const String name = 'ToolRoute';

  static _i14.PageInfo page = _i14.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ToolRouteArgs>();
      return _i12.ToolPage(
        key: args.key,
        agentId: args.agentId,
        tool: args.tool,
      );
    },
  );
}

class ToolRouteArgs {
  const ToolRouteArgs({this.key, required this.agentId, required this.tool});

  final _i15.Key? key;

  final String agentId;

  final _i18.ToolInfo tool;

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
/// [_i13.UpdateRequiredPage]
class UpdateRequiredRoute extends _i14.PageRouteInfo<void> {
  const UpdateRequiredRoute({List<_i14.PageRouteInfo>? children})
    : super(UpdateRequiredRoute.name, initialChildren: children);

  static const String name = 'UpdateRequiredRoute';

  static _i14.PageInfo page = _i14.PageInfo(
    name,
    builder: (data) {
      return const _i13.UpdateRequiredPage();
    },
  );
}
