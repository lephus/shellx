// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:auto_route/auto_route.dart' as _i10;
import 'package:flutter/foundation.dart' as _i12;
import 'package:shellx_mobile/core/core.dart' as _i11;
import 'package:shellx_mobile/features/app/splash_page.dart' as _i7;
import 'package:shellx_mobile/features/app/update_required_page.dart' as _i9;
import 'package:shellx_mobile/features/auth/presentation/pages/login_page.dart'
    as _i2;
import 'package:shellx_mobile/features/auth/presentation/pages/register_page.dart'
    as _i5;
import 'package:shellx_mobile/features/machines/presentation/pages/machine_list_page.dart'
    as _i3;
import 'package:shellx_mobile/features/pairing/presentation/pages/qr_scanner_page.dart'
    as _i4;
import 'package:shellx_mobile/features/settings/presentation/pages/delete_account_page.dart'
    as _i1;
import 'package:shellx_mobile/features/settings/presentation/pages/settings_page.dart'
    as _i6;
import 'package:shellx_mobile/features/terminal/presentation/pages/terminal_page.dart'
    as _i8;

/// generated route for
/// [_i1.DeleteAccountPage]
class DeleteAccountRoute extends _i10.PageRouteInfo<void> {
  const DeleteAccountRoute({List<_i10.PageRouteInfo>? children})
    : super(DeleteAccountRoute.name, initialChildren: children);

  static const String name = 'DeleteAccountRoute';

  static _i10.PageInfo page = _i10.PageInfo(
    name,
    builder: (data) {
      return const _i1.DeleteAccountPage();
    },
  );
}

/// generated route for
/// [_i2.LoginPage]
class LoginRoute extends _i10.PageRouteInfo<void> {
  const LoginRoute({List<_i10.PageRouteInfo>? children})
    : super(LoginRoute.name, initialChildren: children);

  static const String name = 'LoginRoute';

  static _i10.PageInfo page = _i10.PageInfo(
    name,
    builder: (data) {
      return const _i2.LoginPage();
    },
  );
}

/// generated route for
/// [_i3.MachineListPage]
class MachineListRoute extends _i10.PageRouteInfo<void> {
  const MachineListRoute({List<_i10.PageRouteInfo>? children})
    : super(MachineListRoute.name, initialChildren: children);

  static const String name = 'MachineListRoute';

  static _i10.PageInfo page = _i10.PageInfo(
    name,
    builder: (data) {
      return const _i3.MachineListPage();
    },
  );
}

/// generated route for
/// [_i4.QrScannerPage]
class QrScannerRoute extends _i10.PageRouteInfo<QrScannerRouteArgs> {
  QrScannerRoute({
    _i11.Key? key,
    _i4.ScannerViewBuilder scannerBuilder = _i4.cameraScannerView,
    List<_i10.PageRouteInfo>? children,
  }) : super(
         QrScannerRoute.name,
         args: QrScannerRouteArgs(key: key, scannerBuilder: scannerBuilder),
         initialChildren: children,
       );

  static const String name = 'QrScannerRoute';

  static _i10.PageInfo page = _i10.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<QrScannerRouteArgs>(
        orElse: () => const QrScannerRouteArgs(),
      );
      return _i4.QrScannerPage(
        key: args.key,
        scannerBuilder: args.scannerBuilder,
      );
    },
  );
}

class QrScannerRouteArgs {
  const QrScannerRouteArgs({
    this.key,
    this.scannerBuilder = _i4.cameraScannerView,
  });

  final _i11.Key? key;

  final _i4.ScannerViewBuilder scannerBuilder;

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
/// [_i5.RegisterPage]
class RegisterRoute extends _i10.PageRouteInfo<void> {
  const RegisterRoute({List<_i10.PageRouteInfo>? children})
    : super(RegisterRoute.name, initialChildren: children);

  static const String name = 'RegisterRoute';

  static _i10.PageInfo page = _i10.PageInfo(
    name,
    builder: (data) {
      return const _i5.RegisterPage();
    },
  );
}

/// generated route for
/// [_i6.SettingsPage]
class SettingsRoute extends _i10.PageRouteInfo<void> {
  const SettingsRoute({List<_i10.PageRouteInfo>? children})
    : super(SettingsRoute.name, initialChildren: children);

  static const String name = 'SettingsRoute';

  static _i10.PageInfo page = _i10.PageInfo(
    name,
    builder: (data) {
      return const _i6.SettingsPage();
    },
  );
}

/// generated route for
/// [_i7.SplashPage]
class SplashRoute extends _i10.PageRouteInfo<void> {
  const SplashRoute({List<_i10.PageRouteInfo>? children})
    : super(SplashRoute.name, initialChildren: children);

  static const String name = 'SplashRoute';

  static _i10.PageInfo page = _i10.PageInfo(
    name,
    builder: (data) {
      return const _i7.SplashPage();
    },
  );
}

/// generated route for
/// [_i8.TerminalPage]
class TerminalRoute extends _i10.PageRouteInfo<TerminalRouteArgs> {
  TerminalRoute({
    _i12.Key? key,
    required String agentId,
    required String machineName,
    List<_i10.PageRouteInfo>? children,
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

  static _i10.PageInfo page = _i10.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<TerminalRouteArgs>();
      return _i8.TerminalPage(
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

  final _i12.Key? key;

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
/// [_i9.UpdateRequiredPage]
class UpdateRequiredRoute extends _i10.PageRouteInfo<void> {
  const UpdateRequiredRoute({List<_i10.PageRouteInfo>? children})
    : super(UpdateRequiredRoute.name, initialChildren: children);

  static const String name = 'UpdateRequiredRoute';

  static _i10.PageInfo page = _i10.PageInfo(
    name,
    builder: (data) {
      return const _i9.UpdateRequiredPage();
    },
  );
}
