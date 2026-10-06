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
      'Quên mật khẩu? Trên một máy tính khác vẫn đang đăng nhập ShellX, chọn “Đổi mật khẩu…” trong menu khay.';

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
          'Terminal của bạn ở cửa sổ ShellX. ShellX cũng có mặt trên thanh menu: chọn “Ghép nối điện thoại…” ở đó để kết nối điện thoại.',
      'other':
          'Terminal của bạn ở cửa sổ ShellX. ShellX cũng có mặt trong khay hệ thống: chọn “Ghép nối điện thoại…” ở đó để kết nối điện thoại.',
    });
    return '$_temp0';
  }

  @override
  String get onboardingFinish => 'Hoàn tất';

  @override
  String get trayOpenTerminal => 'Mở cửa sổ terminal';

  @override
  String windowTitle(String title) {
    return '$title — ShellX';
  }

  @override
  String get dialogClose => 'Đóng';

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
  String get confirmRemoteOffBody =>
      'Điện thoại đang kết nối sẽ bị ngắt. Các tab terminal trên máy này vẫn chạy.';

  @override
  String get confirmRemoteOffAction => 'Tắt';

  @override
  String get confirmSignOutTitle => 'Đăng xuất khỏi ShellX?';

  @override
  String get confirmSignOutBody =>
      'Điện thoại đang kết nối sẽ bị ngắt và mọi điện thoại đã ghép sẽ bị gỡ. Các tab terminal trên máy này vẫn chạy. Sau khi đăng nhập lại, bạn phải ghép nối lại điện thoại.';

  @override
  String get confirmSignOutAction => 'Đăng xuất';

  @override
  String confirmRevokeTitle(String device) {
    return 'Thu hồi $device?';
  }

  @override
  String get confirmRevokeBody =>
      'Điện thoại này mất quyền truy cập máy tính ngay lập tức và các phiên nó mở bị đóng. Các tab mở trên máy này vẫn chạy. Muốn dùng lại phải ghép nối lại.';

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
          '$count tab đang mở sẽ bị đóng. Điện thoại không kết nối được máy này cho tới khi ShellX chạy lại.',
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
  String get notifyTerminalProblemTitle =>
      'Tiến trình của một phiên terminal có thể vẫn đang chạy';

  @override
  String notifyTerminalProblemBody(int count, String pids) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mã tiến trình shell: $pids',
    );
    return '$_temp0';
  }

  @override
  String get notifyStorageUnreadableTitle =>
      'ShellX không đọc được thông tin đăng nhập đã lưu';

  @override
  String get notifySignOutIncompleteTitle =>
      'Đã đăng xuất, nhưng không xóa được một phần thông tin đăng nhập đã lưu';

  @override
  String get trayTerminalSharing =>
      'Chia sẻ terminal với điện thoại (thử nghiệm)';

  @override
  String get trayNotifyThreshold => 'Thông báo khi lệnh chạy lâu xong';

  @override
  String get trayNotifyOff => 'Tắt';

  @override
  String trayNotifySeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giây',
    );
    return '$_temp0';
  }

  @override
  String trayNotifyMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count phút',
    );
    return '$_temp0';
  }

  @override
  String trayDesktopTerminals(int count) {
    return 'Terminal trên máy tính ($count)';
  }

  @override
  String get trayDisconnectPhone => 'Ngắt điện thoại';

  @override
  String get trayTerminalSharingNeedsSetup =>
      'Chia sẻ terminal cần thiết lập lại…';

  @override
  String notifyDesktopTerminalWatched(String device, String terminal) {
    return '$device đang xem terminal $terminal';
  }

  @override
  String get notifyTerminalSharingFailedTitle =>
      'Không bật được chia sẻ terminal';

  @override
  String get notifyTerminalSharingFailedBody =>
      'Không có gì bị thay đổi. Hãy thử lại.';

  @override
  String get notifyTerminalSharingStartFailedTitle =>
      'Chia sẻ terminal không khởi động được';

  @override
  String get notifyTerminalSharingDisableIncompleteTitle =>
      'Đã tắt chia sẻ terminal, nhưng chưa gỡ được khối ShellX khỏi một số file';

  @override
  String get confirmSharingTitle => 'Chia sẻ terminal với điện thoại?';

  @override
  String get confirmSharingIntro =>
      'Mọi cửa sổ terminal mở từ giờ trở đi sẽ xem và gõ được từ điện thoại đã ghép nối. Các cửa sổ đang mở không được chia sẻ.';

  @override
  String get confirmSharingFiles =>
      'ShellX sẽ sửa các file sau (mỗi file đã có được sao lưu một lần thành <tên>.shellx-backup):';

  @override
  String confirmSharingFileCreated(String path) {
    return '$path (file mới)';
  }

  @override
  String confirmSharingBinary(String path) {
    return 'và chép shellx-term vào $path.';
  }

  @override
  String get confirmSharingBashSkipped =>
      'Không có ~/.bashrc hay ~/.bash_profile nên cửa sổ bash không được chia sẻ.';

  @override
  String get confirmSharingMacNote =>
      'Lưu ý: đóng một cửa sổ terminal đang chạy lệnh sẽ không còn được Terminal.app (và có thể cả iTerm2) hỏi xác nhận.';

  @override
  String get confirmSharingWindowsNote =>
      'Mỗi cửa sổ PowerShell sẽ mở chậm hơn một chút và tốn thêm một ít bộ nhớ.';

  @override
  String confirmSharingPowerShellBlocked(String name) {
    return '$name: chưa cho phép chạy script, nên profile của nó sẽ không chạy cho tới khi cho phép script cục bộ.';
  }

  @override
  String confirmSharingPowerShellGroupPolicy(String name) {
    return '$name: chính sách script do tổ chức của bạn đặt (Group Policy), nên bản PowerShell này sẽ không được chia sẻ.';
  }

  @override
  String get confirmSharingNoPowerShell =>
      'Không tìm thấy PowerShell nào trên máy này.';

  @override
  String get confirmSharingAction => 'Bật';

  @override
  String get confirmAllowScriptsTitle => 'Cho phép script cục bộ?';

  @override
  String confirmAllowScriptsBody(String names) {
    return '$names: chưa cho phép chạy script, nên khối ShellX trong profile không chạy được. Thao tác này đặt chính sách RemoteSigned chỉ cho tài khoản của bạn (Set-ExecutionPolicy -Scope CurrentUser RemoteSigned).';
  }

  @override
  String get confirmAllowScriptsAction =>
      'Cho phép script cục bộ cho tài khoản của tôi';

  @override
  String notifyTerminalSharingFailedFile(String path) {
    return 'ShellX không sửa được $path. Không có gì bị thay đổi.';
  }

  @override
  String notifyAllowScriptsFailedTitle(String name) {
    return 'Không cho phép được script cục bộ cho $name';
  }

  @override
  String get startupFailed =>
      'ShellX không khởi động được. Hãy mở lại; nếu vẫn lỗi, hãy khởi động lại máy.';

  @override
  String get windowsVersionUnsupported =>
      'ShellX cần Windows 10 bản 1809 trở lên.';

  @override
  String terminalExitedLine(int code) {
    return '[Tiến trình đã thoát, mã $code] — Enter để đóng';
  }

  @override
  String get terminalNewTab => 'Tab mới';

  @override
  String terminalNewTabTooltip(String shortcut) {
    return 'Tab mới  $shortcut';
  }

  @override
  String get terminalCloseTab => 'Đóng tab';

  @override
  String get terminalDriverPhone =>
      'Điện thoại đang dùng terminal này — gõ để dùng lại';

  @override
  String get terminalSignedOutStrip => 'Đăng nhập để dùng từ điện thoại';

  @override
  String get terminalSignedOutAction => 'Đăng nhập…';

  @override
  String get terminalEmptyTitle => 'Không có tab nào đang mở';

  @override
  String get terminalEmptyBody =>
      'Mở tab để chạy một shell mới. Phiên bạn mở từ điện thoại cũng hiện ở đây.';

  @override
  String get terminalEmptyAction => 'Mở tab mới';

  @override
  String terminalSessionLimit(int max) {
    return 'Đã mở tối đa $max phiên. Đóng bớt tab để mở tab mới.';
  }

  @override
  String terminalSpawnFailed(String reason) {
    String _temp0 = intl.Intl.selectLogic(reason, {
      'notFound': 'không tìm thấy shell',
      'denied': 'không có quyền chạy shell',
      'other': 'lỗi hệ thống',
    });
    return 'Không mở được shell: $_temp0. Hãy thử lại.';
  }

  @override
  String get toastDismiss => 'Đóng thông báo';

  @override
  String confirmCloseRunningTitle(String title) {
    return 'Đóng “$title”?';
  }

  @override
  String get confirmCloseRunningBody =>
      'Lệnh đang chạy trong tab này sẽ bị dừng.';

  @override
  String get confirmCloseRunningAction => 'Đóng tab';

  @override
  String get sidebarLabel => 'Danh sách tab';

  @override
  String get sidebarStatusIdle => 'đang chờ lệnh';

  @override
  String get sidebarStatusRunning => 'đang chạy lệnh';

  @override
  String sidebarStatusExited(int code) {
    return 'đã thoát, mã $code';
  }

  @override
  String get sidebarPhoneOrigin => 'Mở từ điện thoại';

  @override
  String get sidebarPhoneViewing => 'Điện thoại đang xem';

  @override
  String get sidebarPhoneDriving => 'Điện thoại đang dùng';

  @override
  String get sidebarPhoneOriginSemantics => 'mở từ điện thoại';

  @override
  String get sidebarPhoneViewingSemantics => 'điện thoại đang xem';

  @override
  String get sidebarPhoneDrivingSemantics => 'điện thoại đang dùng';

  @override
  String sidebarPosition(int index, int count) {
    return 'tab $index trên $count';
  }

  @override
  String terminalPaneLabel(String title) {
    return 'Terminal $title';
  }

  @override
  String confirmCloseAllTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Đóng tất cả $count tab?',
    );
    return '$_temp0';
  }

  @override
  String get confirmCloseAllBody =>
      'Mọi shell trong các tab này sẽ bị dừng, kể cả lệnh đang chạy.';

  @override
  String get confirmCloseAllAction => 'Đóng tất cả';

  @override
  String terminalCloseTabTooltip(String shortcut) {
    return 'Đóng tab  $shortcut';
  }

  @override
  String get terminalDriverPhoneShort =>
      'Điện thoại đang dùng — gõ để dùng lại';

  @override
  String get terminalCopy => 'Sao chép';

  @override
  String get terminalPaste => 'Dán';

  @override
  String get terminalSelectAll => 'Chọn tất cả';

  @override
  String get workspaceDefaultName => 'Mặc định';

  @override
  String workspaceNumberedName(int n) {
    return 'Workspace $n';
  }

  @override
  String get workspaceNew => 'Workspace mới';

  @override
  String get workspaceNewTab => 'Tab mới trong workspace này';

  @override
  String get workspaceRename => 'Đổi tên workspace';

  @override
  String get workspaceDelete => 'Xóa workspace';

  @override
  String get workspaceCollapse => 'Thu gọn';

  @override
  String get workspaceExpand => 'Mở rộng';

  @override
  String get workspaceEmptyHint => 'Trống. Kéo tab vào đây hoặc bấm +.';

  @override
  String get workspaceNameField => 'Tên workspace';

  @override
  String workspaceDeleted(String name, String defaultName) {
    return 'Đã xóa workspace “$name”. Các tab đã chuyển về $defaultName.';
  }

  @override
  String workspaceHeaderSemantics(String name, int count) {
    return 'Workspace $name, $count tab';
  }

  @override
  String get workspaceContainsSelected => 'có tab đang chọn';

  @override
  String get workspaceCollapsedState => 'đã thu gọn';

  @override
  String get workspaceExpandedState => 'đã mở rộng';

  @override
  String get tabRename => 'Đổi tên tab';

  @override
  String get tabNameField => 'Tên tab';

  @override
  String get tabUseAutomaticName => 'Dùng tên tự động';

  @override
  String get tabMoveTo => 'Chuyển tới workspace…';

  @override
  String get tabMoveUp => 'Chuyển lên';

  @override
  String get tabMoveDown => 'Chuyển xuống';

  @override
  String tabOpenPort(int port) {
    return 'Mở cổng $port trong trình duyệt';
  }

  @override
  String portOpenTooltip(int port) {
    return 'Mở http://localhost:$port';
  }

  @override
  String portsMoreTooltip(String ports) {
    return 'Cổng đang nghe: $ports';
  }

  @override
  String get portOpenFailed => 'Không mở được trình duyệt.';

  @override
  String sidebarBranch(String branch) {
    return 'nhánh $branch';
  }

  @override
  String sidebarFolder(String path) {
    return 'thư mục $path';
  }

  @override
  String sidebarPorts(int count, String ports) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'cổng $ports',
    );
    return '$_temp0';
  }

  @override
  String sidebarPositionInWorkspace(int index, int count, String workspace) {
    return 'tab $index trên $count trong $workspace';
  }
}
