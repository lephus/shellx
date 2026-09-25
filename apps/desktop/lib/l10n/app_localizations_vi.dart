// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get appTitle => 'ShellX';

  @override
  String get actionCancel => 'Hủy';

  @override
  String get actionClose => 'Đóng';

  @override
  String get authSignInTitle => 'Đăng nhập ShellX';

  @override
  String get authRegisterTitle => 'Tạo tài khoản ShellX';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authPasswordLabel => 'Mật khẩu';

  @override
  String get authConfirmPasswordLabel => 'Nhập lại mật khẩu';

  @override
  String get authSignInButton => 'Đăng nhập';

  @override
  String get authRegisterButton => 'Tạo tài khoản';

  @override
  String get authSwitchToRegister => 'Chưa có tài khoản? Đăng ký';

  @override
  String get authSwitchToSignIn => 'Đã có tài khoản? Đăng nhập';

  @override
  String get authForgotPasswordHint =>
      'Quên mật khẩu? Mở ShellX trên máy tính vẫn đang đăng nhập và chọn “Đổi mật khẩu…” trong menu.';

  @override
  String get authSignedOutNotice => 'Bạn đã bị đăng xuất. Hãy đăng nhập lại.';

  @override
  String get errorEmailInvalid => 'Hãy nhập địa chỉ email hợp lệ.';

  @override
  String get errorPasswordLength => 'Mật khẩu phải dài 8–128 ký tự.';

  @override
  String get errorPasswordMismatch => 'Hai mật khẩu không khớp.';

  @override
  String get errorDisposableEmail =>
      'Không chấp nhận email tạm thời. Hãy dùng địa chỉ email thật.';

  @override
  String get errorEmailTaken => 'Email này đã được đăng ký. Hãy đăng nhập.';

  @override
  String get errorInvalidCredentials => 'Email hoặc mật khẩu không đúng.';

  @override
  String get errorRateLimited => 'Thử lại sau ít phút.';

  @override
  String get errorNetwork =>
      'Không kết nối được máy chủ ShellX. Hãy kiểm tra kết nối Internet.';

  @override
  String get errorAgentOnly =>
      'Chỉ máy tính đang đăng nhập mới đổi được mật khẩu.';

  @override
  String errorUnexpected(String code) {
    return 'Đã có lỗi ($code). Hãy thử lại.';
  }

  @override
  String get onboardingTitle => 'Sắp xong rồi';

  @override
  String get onboardingLaunchAtStartup => 'Khởi động ShellX cùng hệ thống';

  @override
  String get onboardingFullDiskTitle =>
      'Quyền truy cập toàn bộ ổ đĩa (không bắt buộc)';

  @override
  String get onboardingFullDiskBody =>
      'Lệnh chạm vào Desktop, Documents hoặc Downloads sẽ làm macOS hiện hộp thoại xin quyền trên màn hình máy này, và bạn không trả lời được từ điện thoại. Cấp quyền Full Disk Access cho ShellX để tránh việc đó.';

  @override
  String get onboardingOpenSettings => 'Mở Cài đặt hệ thống';

  @override
  String get onboardingSleepTitle => 'Chế độ ngủ';

  @override
  String get onboardingSleepBody =>
      'ShellX giữ máy không tự ngủ khi để yên. Gập nắp laptop thì máy vẫn ngủ và điện thoại sẽ không kết nối được.';

  @override
  String onboardingTrayHint(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'macos':
          'ShellX giờ nằm trên thanh menu. Chọn “Ghép nối điện thoại…” ở đó để kết nối điện thoại.',
      'other':
          'ShellX giờ nằm trong khay hệ thống. Chọn “Ghép nối điện thoại…” ở đó để kết nối điện thoại.',
    });
    return '$_temp0';
  }

  @override
  String get onboardingFinish => 'Hoàn tất';

  @override
  String get trayTooltip => 'ShellX';

  @override
  String trayStatusConnected(String email) {
    return 'Đã kết nối — $email';
  }

  @override
  String trayStatusConnecting(String email) {
    return 'Đang kết nối — $email';
  }

  @override
  String get trayStatusReconnecting => 'Mất kết nối — đang thử lại…';

  @override
  String get trayStatusRemoteOff => 'Đã tắt truy cập từ xa';

  @override
  String get trayStatusReplaced =>
      'Một bản ShellX khác đã kết nối thay máy này';

  @override
  String get trayStatusSignedOut => 'Chưa đăng nhập';

  @override
  String get trayReconnect => 'Kết nối lại';

  @override
  String get trayRemoteAccess => 'Cho phép truy cập từ xa';

  @override
  String traySessions(int count) {
    return 'Phiên đang hoạt động ($count)';
  }

  @override
  String traySessionItem(String shell, int index) {
    return '$shell $index';
  }

  @override
  String traySessionItemAttached(String shell, int index, String device) {
    return '$shell $index — $device';
  }

  @override
  String get traySessionClose => 'Đóng';

  @override
  String get trayCloseAll => 'Đóng tất cả';

  @override
  String get trayPairPhone => 'Ghép nối điện thoại…';

  @override
  String get trayPairedDevices => 'Thiết bị đã ghép';

  @override
  String get trayRevoke => 'Thu hồi';

  @override
  String get trayNoDevices => 'Chưa ghép thiết bị nào';

  @override
  String get trayKeepAwake => 'Giữ máy không ngủ';

  @override
  String get trayLaunchAtStartup => 'Khởi động cùng hệ thống';

  @override
  String get trayChangePassword => 'Đổi mật khẩu…';

  @override
  String get traySignOut => 'Đăng xuất';

  @override
  String get traySignIn => 'Đăng nhập…';

  @override
  String get trayQuit => 'Thoát';

  @override
  String trayDownloadUpdate(String version) {
    return 'Tải ShellX $version…';
  }

  @override
  String get confirmRemoteOffTitle => 'Tắt truy cập từ xa?';

  @override
  String confirmRemoteOffBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count phiên đang mở sẽ bị đóng.',
    );
    return '$_temp0';
  }

  @override
  String get confirmRemoteOffAction => 'Tắt';

  @override
  String get confirmSignOutTitle => 'Đăng xuất khỏi ShellX?';

  @override
  String get confirmSignOutBody =>
      'Mọi phiên sẽ bị đóng và mọi điện thoại đã ghép sẽ bị gỡ. Sau khi đăng nhập lại, bạn phải ghép nối lại điện thoại.';

  @override
  String get confirmSignOutAction => 'Đăng xuất';

  @override
  String confirmRevokeTitle(String device) {
    return 'Thu hồi $device?';
  }

  @override
  String get confirmRevokeBody =>
      'Điện thoại này mất quyền truy cập máy tính ngay lập tức và các phiên của nó bị đóng. Muốn dùng lại phải ghép nối lại.';

  @override
  String get confirmRevokeAction => 'Thu hồi';

  @override
  String get confirmQuitTitle => 'Thoát ShellX?';

  @override
  String confirmQuitBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count phiên đang mở sẽ bị đóng. Điện thoại không kết nối được máy này cho tới khi ShellX chạy lại.',
    );
    return '$_temp0';
  }

  @override
  String get confirmQuitAction => 'Thoát';

  @override
  String get pairingTitle => 'Ghép nối điện thoại';

  @override
  String get pairingInstructions =>
      'Mở ShellX trên điện thoại (đăng nhập cùng tài khoản), chạm vào máy tính này rồi quét mã.';

  @override
  String pairingExpiresIn(String time) {
    return 'Mã hết hạn sau $time';
  }

  @override
  String get pairingExpired => 'Mã đã hết hạn.';

  @override
  String get pairingNewCode => 'Tạo mã mới';

  @override
  String get pairingOfflineWarning =>
      'Chưa kết nối được máy chủ ShellX. Điện thoại chỉ ghép nối được khi có kết nối trở lại.';

  @override
  String get pairingSecretWarning =>
      'Ai quét được mã này khi đăng nhập tài khoản của bạn sẽ điều khiển được máy tính này. Đừng chia sẻ mã.';

  @override
  String get changePasswordTitle => 'Đổi mật khẩu';

  @override
  String get changePasswordNew => 'Mật khẩu mới';

  @override
  String get changePasswordConfirm => 'Nhập lại mật khẩu mới';

  @override
  String get changePasswordSubmit => 'Đổi mật khẩu';

  @override
  String get changePasswordNote =>
      'Các thiết bị khác sẽ bị đăng xuất. Ghép nối được giữ nguyên.';

  @override
  String get changePasswordDone =>
      'Đã đổi mật khẩu. Điện thoại cần đăng nhập lại bằng mật khẩu mới.';

  @override
  String notifySessionOpened(String device) {
    return '$device vừa mở phiên terminal';
  }

  @override
  String notifyPaired(String device) {
    return 'Đã ghép nối với $device';
  }

  @override
  String notifyUpdateAvailableTitle(String version) {
    return 'Đã có ShellX $version';
  }

  @override
  String get notifyUpdateAvailableBody => 'Bấm để tải về.';

  @override
  String get notifyUpdateRequiredTitle => 'Cần cập nhật app';

  @override
  String notifyUpdateRequiredBody(String version) {
    return 'Phiên bản này không còn được hỗ trợ. Bấm để tải ShellX $version.';
  }

  @override
  String get notifySignedOutTitle => 'ShellX đã bị đăng xuất';

  @override
  String get notifySignedOutBody => 'Đăng nhập lại để cho phép truy cập từ xa.';

  @override
  String get notifyAlreadyRunningTitle => 'ShellX đang chạy';

  @override
  String notifyAlreadyRunningBody(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'macos': 'Tìm ShellX trên thanh menu.',
      'other': 'Tìm ShellX trong khay hệ thống.',
    });
    return '$_temp0';
  }

  @override
  String get notifyTerminalProblemTitle =>
      'Tiến trình của một phiên terminal có thể vẫn đang chạy';

  @override
  String get windowsVersionUnsupported =>
      'ShellX cần Windows 10 bản 1809 trở lên.';
}
