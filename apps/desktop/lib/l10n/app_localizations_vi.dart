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
  String get workspaceEmptyHint => 'Trống — kéo tab vào đây';

  @override
  String get workspaceDeleteDefaultReason =>
      'Không xóa được workspace Mặc định';

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
  String tabMoveToTitle(String name) {
    return 'Chuyển “$name” tới';
  }

  @override
  String get tabOpenPortMenu => 'Mở cổng trong trình duyệt…';

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

  @override
  String get attentionBell => 'Chuông';

  @override
  String attentionBellRepeat(int count) {
    return 'Chuông ×$count';
  }

  @override
  String get attentionBellBody => 'Chuông trong tab này';

  @override
  String attentionUnreadCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count thông báo chưa đọc',
    );
    return '$_temp0';
  }

  @override
  String attentionRowSemantics(int count, String text) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count thông báo chưa đọc',
    );
    return '$_temp0, mới nhất: $text';
  }

  @override
  String get attentionMarkRead => 'Đánh dấu đã đọc';

  @override
  String get attentionMarkAllRead => 'Đánh dấu tất cả đã đọc';

  @override
  String attentionAnnounce(String tab, String text) {
    return 'Thông báo mới từ $tab: $text';
  }

  @override
  String get workspaceHasUnread => 'có thông báo chưa đọc';

  @override
  String terminalPaneUnreadLabel(String title) {
    return 'Terminal $title, có thông báo chưa đọc';
  }

  @override
  String get notificationsPanelTitle => 'Thông báo';

  @override
  String notificationsPanelTooltip(String shortcut) {
    return 'Thông báo  $shortcut';
  }

  @override
  String notificationsPanelNextHint(String shortcut) {
    return 'Chưa đọc tiếp theo  $shortcut';
  }

  @override
  String notificationsPanelOpened(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Thông báo, $count mục',
    );
    return '$_temp0';
  }

  @override
  String get notificationsTabClosed => 'Tab đã đóng';

  @override
  String get notificationsTimeNow => 'vừa xong';

  @override
  String notificationsTimeMinutes(int count) {
    return '$count phút';
  }

  @override
  String notificationsTimeHours(int count) {
    return '$count giờ';
  }

  @override
  String notificationsTimeYesterday(String time) {
    return 'Hôm qua $time';
  }

  @override
  String notificationsTimeDate(
    String month,
    String day,
    String dayPadded,
    String time,
  ) {
    return '$dayPadded/$month $time';
  }

  @override
  String notificationsMonthShort(String month) {
    String _temp0 = intl.Intl.selectLogic(month, {
      'm1': '01',
      'm2': '02',
      'm3': '03',
      'm4': '04',
      'm5': '05',
      'm6': '06',
      'm7': '07',
      'm8': '08',
      'm9': '09',
      'm10': '10',
      'm11': '11',
      'm12': '12',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String get notificationsItemUnread => 'chưa đọc';

  @override
  String get noUnreadNotifications => 'Không còn thông báo chưa đọc';

  @override
  String systemNotifyCoalesced(int count, String text) {
    return '$count thông báo mới · $text';
  }

  @override
  String get trayNotifications => 'Thông báo';

  @override
  String get trayDesktopNotifications => 'Thông báo trên máy tính';

  @override
  String get trayDesktopNotificationsUnfocused =>
      'Chỉ khi cửa sổ không ở phía trước';

  @override
  String get paneSplitRight => 'Chia sang phải';

  @override
  String get paneSplitDown => 'Chia xuống dưới';

  @override
  String get paneZoom => 'Phóng to pane';

  @override
  String get paneUnzoom => 'Bỏ phóng to';

  @override
  String get paneEqualize => 'Cân bằng pane';

  @override
  String get paneClose => 'Đóng pane';

  @override
  String paneCloseTooltip(String shortcut) {
    return 'Đóng pane  $shortcut';
  }

  @override
  String paneZoomedIndicator(int index, int count) {
    return 'Phóng to · $index/$count';
  }

  @override
  String paneRegionLabel(int index, int count, String title) {
    return 'Pane $index trên $count — $title';
  }

  @override
  String paneRegionUnreadLabel(int index, int count, String title) {
    return 'Pane $index trên $count — $title, có thông báo chưa đọc';
  }

  @override
  String get paneDividerLabel => 'Đường chia pane';

  @override
  String get paneSplitNoRoom => 'Không đủ chỗ để chia pane này';

  @override
  String paneAnnounceSplit(int index, int count) {
    return 'Đã chia, pane $index trên $count';
  }

  @override
  String paneAnnounceClosed(int count) {
    return 'Đã đóng pane, còn $count';
  }

  @override
  String get paneAnnounceZoomed => 'Đã phóng to pane';

  @override
  String get paneAnnounceUnzoomed => 'Đã bỏ phóng to';

  @override
  String sidebarPaneCount(int count) {
    return '$count pane';
  }

  @override
  String get terminalCloseTabAllPanes => 'Đóng tab (mọi pane)';

  @override
  String get confirmCloseRunningPaneBody =>
      'Lệnh đang chạy trong pane này sẽ bị dừng.';

  @override
  String get confirmCloseRunningPaneAction => 'Đóng pane';

  @override
  String confirmCloseRunningPanesBody(int count) {
    return '$count pane đang chạy lệnh sẽ bị dừng.';
  }

  @override
  String get confirmCloseAlwaysBody => 'Shell trong tab này sẽ đóng.';

  @override
  String confirmCloseAlwaysPanesBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pane trong tab này sẽ đóng.',
    );
    return '$_temp0';
  }

  @override
  String get confirmClosePaneAlwaysBody => 'Shell trong pane này sẽ đóng.';

  @override
  String terminalRestoredDivider(String time) {
    return '— Phiên được khôi phục · $time —';
  }

  @override
  String restoreTimeYesterday(String time) {
    return 'hôm qua $time';
  }

  @override
  String get trayTerminal => 'Terminal';

  @override
  String get trayRestoreScrollback => 'Lưu nội dung terminal khi thoát';

  @override
  String get trayClearSavedScrollback => 'Xóa nội dung đã lưu';

  @override
  String restoreAbnormalStrip(int count, String time) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'ShellX đã đóng bất thường lần trước. Đã mở lại $count tab; nội dung tính tới $time.',
    );
    return '$_temp0';
  }

  @override
  String restoreAbnormalNoText(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ShellX đã đóng bất thường lần trước. Đã mở lại $count tab.',
    );
    return '$_temp0';
  }

  @override
  String get restoreStripCloseLabel => 'Đóng thông báo khôi phục';

  @override
  String restorePanesFailed(int count) {
    return 'Không mở lại được $count pane';
  }

  @override
  String get cliNoticeSource => 'Dòng lệnh';

  @override
  String get trayCommandLine => 'Dòng lệnh';

  @override
  String get trayCliControl => 'Cho phép điều khiển ShellX bằng dòng lệnh';

  @override
  String get trayCliAllowExternal => 'Cho phép terminal khác';

  @override
  String get trayCliInstallPath => 'Cài lệnh shellx cho mọi terminal…';

  @override
  String get trayCliRemovePath => 'Gỡ lệnh shellx khỏi terminal khác';

  @override
  String get trayCliCopySkills => 'Sao chép lệnh cài skill cho agent';

  @override
  String get cliSkillsCopied =>
      'Đã sao chép “shellx skills install” — dán vào terminal';

  @override
  String get cliPathInstalled =>
      'Đã cài lệnh shellx. Để terminal khác điều khiển được ShellX, hãy bật thêm “Cho phép terminal khác” trong menu Dòng lệnh ở khay.';

  @override
  String cliPathFailed(String path) {
    return 'Không cài được lệnh shellx. Hãy thêm $path vào PATH.';
  }

  @override
  String cliPathRemoveFailed(String path) {
    return 'Không gỡ được lệnh shellx. Hãy tự gỡ $path.';
  }

  @override
  String get agentChip => 'Agent';

  @override
  String get agentChipTooltip =>
      'Một chương trình đang điều khiển tab này qua dòng lệnh ShellX';

  @override
  String cliAnnounceAgent(String tab) {
    return 'Agent đang điều khiển $tab';
  }

  @override
  String cliPathNotOnPath(String file, String line) {
    return 'Đã cài lệnh shellx vào /usr/local/bin nhưng shell của bạn không tìm ở đó. Hãy thêm dòng này vào $file: $line';
  }

  @override
  String get userCommandNoTerminal => 'Không có terminal để chạy lệnh này';

  @override
  String configOpenFailed(String path) {
    return 'Không mở được $path';
  }

  @override
  String sequencePending(String shortcut) {
    return '$shortcut …';
  }

  @override
  String sequencePendingAnnounce(String shortcut) {
    return 'Đã bấm $shortcut, chờ phím tiếp theo';
  }

  @override
  String configProblemsToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cấu hình có $count vấn đề',
    );
    return '$_temp0';
  }

  @override
  String get configProblemsShow => 'Xem';

  @override
  String get configReloaded => 'Đã tải lại cấu hình';

  @override
  String get configGhosttyNotice =>
      'Đang dùng font và màu từ cấu hình Ghostty (tắt bằng ghostty-config = false)';

  @override
  String get configProblemsTitle => 'Vấn đề trong cấu hình';

  @override
  String get configProblemsNone => 'Cấu hình không có vấn đề.';

  @override
  String configProblemWhere(String file, int line) {
    return '$file, dòng $line';
  }

  @override
  String configProblemLine(int line) {
    return 'dòng $line';
  }

  @override
  String get configSeverityError => 'Lỗi';

  @override
  String get configSeverityWarning => 'Cảnh báo';

  @override
  String get configSeverityInfo => 'Ghi chú';

  @override
  String get configOpenFile => 'Mở file cấu hình';

  @override
  String get configReload => 'Tải lại cấu hình';

  @override
  String get configProblemSyntax =>
      'Dòng không có dấu “=” (dạng đúng: khoá = giá trị)';

  @override
  String configProblemBadKey(String key) {
    return '“$key” không phải tên khoá hợp lệ';
  }

  @override
  String configProblemUnknownKey(String key) {
    return 'ShellX không có khoá “$key”';
  }

  @override
  String configProblemBadValue(String key, String value, String hint) {
    return '$key: “$value” không hợp lệ (cần $hint)';
  }

  @override
  String configProblemOutOfRange(
    String key,
    String value,
    String hint,
    String detail,
  ) {
    return '$key: $value nằm ngoài $hint, đã dùng $detail';
  }

  @override
  String configProblemDuplicate(String key, String detail) {
    return '$key: thay cho dòng $detail';
  }

  @override
  String configProblemIncludeMissing(String value) {
    return 'Không tìm thấy file “$value”';
  }

  @override
  String configProblemIncludeCycle(String value) {
    return '“$value” đã được nạp (vòng lặp config-file)';
  }

  @override
  String get configProblemIncludeDepth => 'config-file lồng quá 4 tầng';

  @override
  String get configProblemIncludeLimit => 'Quá 64 file cấu hình — bỏ phần sau';

  @override
  String get configProblemUnreadable =>
      'Không đọc được file — đang giữ cấu hình trước';

  @override
  String get configProblemNotUtf8 =>
      'File không phải UTF-8 — đang giữ cấu hình trước';

  @override
  String get configProblemTooLarge =>
      'File lớn hơn 256 KiB — đang giữ cấu hình trước';

  @override
  String configProblemThemeNotFound(String value) {
    return 'Không tìm thấy chủ đề “$value”';
  }

  @override
  String configProblemFontNotFound(String value) {
    return 'Không tìm thấy font “$value” — dùng JetBrains Mono';
  }

  @override
  String configProblemFontNotMonospace(String value) {
    return 'Font “$value” không đơn cách — cột có thể lệch';
  }

  @override
  String configProblemLowContrast(String detail) {
    return 'Chữ và nền tương phản thấp ($detail:1, nên từ 4,5:1)';
  }

  @override
  String configProblemUnsupportedValue(String key, String value, String hint) {
    return '$key = $value chưa được hỗ trợ (dùng $hint)';
  }

  @override
  String configProblemNotOnThisPlatform(String key) {
    return '$key chỉ có tác dụng trên macOS';
  }

  @override
  String configProblemBadTrigger(String value) {
    return '“$value” không phải tổ hợp phím hợp lệ';
  }

  @override
  String configProblemUnknownAction(String value) {
    return 'Không có action “$value”';
  }

  @override
  String configProblemBadActionParam(String value, String hint) {
    return '“$value” không hợp lệ (cần $hint)';
  }

  @override
  String configProblemReservedTrigger(String value) {
    return 'Hệ điều hành giữ $value';
  }

  @override
  String configProblemPlainKeyTrigger(String value) {
    return '$value dùng để gõ chữ — thêm Ctrl, Alt hoặc ⌘';
  }

  @override
  String get configProblemRegionTrigger =>
      'F6 và Shift+F6 luôn dùng để chuyển vùng';

  @override
  String configProblemShellKeyTrigger(String value) {
    return '$value sẽ không còn tới shell';
  }

  @override
  String configProblemOptionKeyTrigger(String value) {
    return '$value sẽ không còn gõ ký tự Option';
  }

  @override
  String configProblemAltGrTrigger(String value) {
    return '$value chỉ chạy với Alt trái; AltGr vẫn gõ ký tự';
  }

  @override
  String configProblemMissionControlTrigger(String value) {
    return 'Mission Control có thể giữ $value';
  }

  @override
  String configProblemUnsupportedPrefix(String value) {
    return 'Tiền tố “$value” không được hỗ trợ';
  }

  @override
  String get configProblemSequenceTooLong => 'Chuỗi phím tối đa 2 bước';

  @override
  String configProblemSequencePrefixShadows(String value) {
    return '$value là đầu một chuỗi phím nên không còn chạy một mình';
  }

  @override
  String configProblemSequenceRepeatsPrefix(String value) {
    return 'Chuỗi này không chạy được: bấm $value hai lần sẽ gửi chính phím đó';
  }

  @override
  String configProblemUnknownCommand(String value) {
    return 'Không có lệnh “$value”';
  }

  @override
  String get configProblemCommandLimit => 'Quá 200 lệnh — bỏ phần sau';

  @override
  String configProblemLimit(String detail) {
    return '$detail vấn đề — chỉ hiện 100 vấn đề đầu tiên';
  }

  @override
  String get configProblemInternal =>
      'Lỗi không mong đợi — đang giữ cấu hình trước';

  @override
  String get trayConfig => 'Cấu hình';

  @override
  String get trayConfigOpen => 'Mở file cấu hình';

  @override
  String get trayConfigReload => 'Tải lại cấu hình';

  @override
  String get trayConfigShortcuts => 'Phím tắt…';

  @override
  String trayConfigProblems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '⚠ $count vấn đề cấu hình…',
    );
    return '$_temp0';
  }

  @override
  String get paletteTitle => 'Bảng lệnh';

  @override
  String get paletteSearchLabel => 'Tìm lệnh';

  @override
  String get paletteSearchHint => 'Gõ tên lệnh…';

  @override
  String get paletteNoResults => 'Không có lệnh nào khớp';

  @override
  String paletteResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lệnh',
    );
    return '$_temp0';
  }

  @override
  String get paletteKindUserCommand => 'Lệnh của bạn';

  @override
  String get paletteKindSnippet => 'Đoạn chữ';

  @override
  String get paletteKindConfig => 'Cấu hình';

  @override
  String get actionNewTab => 'Tab mới';

  @override
  String get actionCloseSurface => 'Đóng pane hoặc tab';

  @override
  String get actionCloseTab => 'Đóng cả tab';

  @override
  String get actionNewWorkspace => 'Workspace mới';

  @override
  String get actionSshConnect => 'Kết nối SSH';

  @override
  String get actionTmuxAttach => 'Gắn phiên tmux';

  @override
  String get actionToggleNotifications => 'Bảng thông báo';

  @override
  String get actionJumpToUnread => 'Tới thông báo chưa đọc';

  @override
  String get actionCopy => 'Sao chép';

  @override
  String get actionPaste => 'Dán';

  @override
  String get actionSelectAll => 'Chọn tất cả';

  @override
  String actionGotoTab(String n) {
    return 'Tới tab $n';
  }

  @override
  String get actionNextTab => 'Tab sau';

  @override
  String get actionPreviousTab => 'Tab trước';

  @override
  String get actionSplitRight => 'Chia sang phải';

  @override
  String get actionSplitDown => 'Chia xuống dưới';

  @override
  String actionFocusPane(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'left': 'Sang pane bên trái',
      'right': 'Sang pane bên phải',
      'up': 'Lên pane trên',
      'other': 'Xuống pane dưới',
    });
    return '$_temp0';
  }

  @override
  String actionResizePane(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'left': 'Dời đường chia sang trái',
      'right': 'Dời đường chia sang phải',
      'up': 'Dời đường chia lên',
      'other': 'Dời đường chia xuống',
    });
    return '$_temp0';
  }

  @override
  String get actionToggleZoom => 'Phóng to / bỏ phóng to pane';

  @override
  String get actionEqualize => 'Cân bằng pane';

  @override
  String get actionFontBigger => 'Chữ to hơn';

  @override
  String get actionFontSmaller => 'Chữ nhỏ hơn';

  @override
  String get actionFontReset => 'Cỡ chữ mặc định';

  @override
  String get actionNextRegion => 'Vùng tiếp theo';

  @override
  String get actionPreviousRegion => 'Vùng trước';

  @override
  String get actionReloadConfig => 'Tải lại cấu hình';

  @override
  String get actionOpenConfig => 'Mở file cấu hình';

  @override
  String get actionCommandPalette => 'Bảng lệnh';

  @override
  String get actionShowShortcuts => 'Phím tắt…';

  @override
  String get actionShowConfigProblems => 'Xem vấn đề cấu hình';

  @override
  String actionRunCommand(String name) {
    return 'Chạy “$name”';
  }

  @override
  String get actionSendText => 'Gửi chữ vào terminal';

  @override
  String get actionIgnore => 'Bỏ qua phím';

  @override
  String get shortcutsTitle => 'Phím tắt';

  @override
  String get shortcutsSearchLabel => 'Tìm phím tắt';

  @override
  String shortcutsGroup(String group) {
    String _temp0 = intl.Intl.selectLogic(group, {
      'tabs': 'Tab',
      'panes': 'Pane',
      'notifications': 'Thông báo',
      'editing': 'Chỉnh sửa',
      'font': 'Cỡ chữ',
      'browser': 'Trình duyệt',
      'window': 'Cửa sổ',
      'config': 'Cấu hình',
      'other': 'Lệnh của bạn',
    });
    return '$_temp0';
  }

  @override
  String get shortcutsAdd => 'Thêm phím';

  @override
  String shortcutsAddFor(String action) {
    return 'Thêm phím cho “$action”';
  }

  @override
  String get shortcutsReset => 'Đặt lại';

  @override
  String shortcutsResetFor(String action) {
    return 'Đặt lại “$action”';
  }

  @override
  String shortcutsRemove(String shortcut) {
    return 'Bỏ $shortcut';
  }

  @override
  String get shortcutsNone => 'Chưa gán';

  @override
  String get shortcutsRecording => 'Bấm tổ hợp phím… (Esc để huỷ)';

  @override
  String shortcutsHeld(String keys) {
    return '$keys…';
  }

  @override
  String shortcutsConflict(String shortcut, String action) {
    return '$shortcut đang dùng cho “$action”.';
  }

  @override
  String get shortcutsReplace => 'Thay thế';

  @override
  String get shortcutsCancel => 'Huỷ';

  @override
  String shortcutsOverridden(String file, int line) {
    return 'Một dòng sau trong $file:$line ghi đè phím này';
  }

  @override
  String shortcutsFromFile(int line) {
    return 'Đặt trong file cấu hình, dòng $line';
  }

  @override
  String shortcutsAssigned(String shortcut, String action) {
    return 'Đã gán $shortcut cho “$action”';
  }

  @override
  String shortcutsRemoved(String shortcut) {
    return 'Đã bỏ $shortcut';
  }

  @override
  String shortcutsResetDone(String action) {
    return 'Đã đặt lại “$action”';
  }

  @override
  String get shortcutsFooter => 'Phím viết tay trong file vẫn được giữ.';

  @override
  String configWriteFailed(String path) {
    return 'Không lưu được phím tắt vào $path';
  }

  @override
  String get sshConnectMenu => 'Kết nối SSH…';

  @override
  String get tmuxAttachMenu => 'Gắn phiên tmux…';

  @override
  String get sshDialogTitle => 'Kết nối tới máy chủ';

  @override
  String get sshDialogTabSsh => 'SSH';

  @override
  String get sshDialogTabTmux => 'tmux';

  @override
  String get sshHostLabel => 'Máy chủ';

  @override
  String get sshHostHint => 'devbox hoặc user@host:2222';

  @override
  String get sshHostInvalid => 'Không phải tên máy chủ hợp lệ';

  @override
  String get sshSuggestionsConfig => 'Trong ~/.ssh/config';

  @override
  String get sshSuggestionsRecent => 'Gần đây';

  @override
  String sshSuggestionsCount(int count) {
    return '$count gợi ý';
  }

  @override
  String get sshRemoteDirLabel => 'Thư mục trên máy chủ (không bắt buộc)';

  @override
  String get sshRemoteDirInvalid => 'Đường dẫn phải bắt đầu bằng / hoặc ~';

  @override
  String get sshNoHookLabel => 'Không cài hook ShellX trên máy này';

  @override
  String get sshRemoteDirNeedsHook => 'Cần hook trên máy chủ';

  @override
  String get sshNoHookHelp =>
      'Hook cho ShellX biết thư mục, nhánh và cổng trên máy chủ. Tắt khi máy chủ không phải Unix.';

  @override
  String get sshConnectAction => 'Kết nối';

  @override
  String get sshUnavailable => 'Không tìm thấy lệnh ssh trên máy này';

  @override
  String get sshUnavailableWindows =>
      'Không tìm thấy ssh. Bật “OpenSSH Client” trong Settings → Apps → Optional features.';

  @override
  String get tmuxSourceLabel => 'Phiên tmux trên';

  @override
  String get tmuxSourceLocal => 'Máy này';

  @override
  String get tmuxLoading => 'Đang lấy danh sách phiên…';

  @override
  String get tmuxEmpty => 'Chưa có phiên tmux nào';

  @override
  String tmuxUnavailable(String where) {
    return 'tmux chưa được cài trên $where';
  }

  @override
  String get tmuxUnavailableLocal => 'tmux chưa được cài trên máy này';

  @override
  String tmuxListFailed(String where) {
    return 'Không lấy được danh sách phiên trên $where. Kết nối SSH tới máy này một lần (để không phải nhập mật khẩu) rồi thử lại.';
  }

  @override
  String get tmuxRetry => 'Thử lại';

  @override
  String tmuxWindows(int count) {
    return '$count cửa sổ';
  }

  @override
  String get tmuxAttachedElsewhere => 'đang gắn ở nơi khác';

  @override
  String tmuxLastActive(String time) {
    return 'hoạt động $time';
  }

  @override
  String get tmuxAttachAction => 'Gắn';

  @override
  String get tmuxNewLabel => 'Tên phiên mới';

  @override
  String get tmuxNameInvalid =>
      'Tên chỉ gồm tối đa 64 ký tự, không có “:” hay “.”';

  @override
  String get tmuxCreateAction => 'Tạo và gắn';

  @override
  String sidebarRemoteMark(String host) {
    return 'SSH: $host';
  }

  @override
  String sidebarTmuxMark(String name) {
    return 'tmux: $name';
  }

  @override
  String sidebarTmuxRemoteMark(String name, String host) {
    return 'tmux: $name · $host';
  }

  @override
  String sshStateConnecting(String host) {
    return 'Đang kết nối tới $host';
  }

  @override
  String sshStateDisconnected(String host) {
    return 'Mất kết nối tới $host';
  }

  @override
  String sshStateFailed(String host) {
    return 'Không kết nối được tới $host';
  }

  @override
  String sshRetryIn(int seconds) {
    return 'Thử lại sau $seconds giây';
  }

  @override
  String get sshRetrying => 'Đang kết nối lại…';

  @override
  String get sshRetryWaiting => 'Tự động thử lại';

  @override
  String get sshNeedsSignIn => 'Cần đăng nhập';

  @override
  String get sshAutoRetryStopped => 'Đã ngừng tự kết nối lại';

  @override
  String get sshFailedHookHint => 'Máy chủ có thể không chạy được hook ShellX';

  @override
  String get sshReconnectAction => 'Kết nối lại';

  @override
  String get sshRetryAction => 'Thử lại';

  @override
  String get sshRetryPlainAction => 'Thử lại không dùng hook';

  @override
  String get sshClosePaneAction => 'Đóng pane';

  @override
  String get sshTmuxHint =>
      'Chạy trong tmux để chương trình vẫn chạy khi mất kết nối';

  @override
  String sshDisconnectedLine(String host) {
    return '[Mất kết nối tới $host] — Enter để kết nối lại';
  }

  @override
  String sshFailedLine(String host) {
    return '[Không kết nối được tới $host] — Enter để thử lại';
  }

  @override
  String sshReconnectedDivider(String time) {
    return '— Đã kết nối lại · $time —';
  }

  @override
  String workspaceNewRemoteTab(String host) {
    return 'Tab SSH mới tới $host';
  }

  @override
  String get workspaceNewLocalTab => 'Tab cục bộ mới';

  @override
  String get workspaceReconnectAll => 'Kết nối lại mọi pane';

  @override
  String workspaceRemoteLabel(String host) {
    return 'Workspace SSH $host';
  }

  @override
  String get rowReconnect => 'Kết nối lại';

  @override
  String get paneSplitLocalRight => 'Chia cục bộ sang phải';

  @override
  String remotePortTooltip(int port, String host) {
    return 'Mở cổng $port trên $host (chuyển tiếp qua SSH)';
  }

  @override
  String remotePortForwarded(int local, String host, int port) {
    return 'localhost:$local → $host:$port';
  }

  @override
  String remotePortForwardFailed(int port) {
    return 'Không chuyển tiếp được cổng $port';
  }

  @override
  String get sshTrayMenu => 'SSH';

  @override
  String get sshTrayHook =>
      'Cài hook ShellX trên máy chủ (thư mục, nhánh, cổng)';

  @override
  String get sshTrayClearRecent => 'Xóa danh sách máy gần đây';

  @override
  String get sshRecentCleared => 'Đã xóa danh sách máy gần đây';

  @override
  String sshAnnounceConnected(String host) {
    return 'Đã kết nối tới $host';
  }

  @override
  String sshAnnounceDisconnected(String host) {
    return 'Mất kết nối tới $host';
  }

  @override
  String sshAnnounceReconnected(String host) {
    return 'Đã kết nối lại tới $host';
  }

  @override
  String paneRemoteSuffix(String host) {
    return ', trên $host';
  }

  @override
  String get trayQuitUi => 'Thoát';

  @override
  String get trayQuitAll => 'Thoát hoàn toàn';

  @override
  String get appMenuQuitAll => 'Thoát hoàn toàn';

  @override
  String get quitUiExplainedTitle => 'Shell vẫn chạy sau khi thoát';

  @override
  String quitUiExplainedBody(int count) {
    return '$count tab vẫn chạy nền và điện thoại vẫn kết nối được. Mở lại ShellX để quay về đúng chỗ. Muốn dừng mọi shell, chọn Thoát hoàn toàn (⌥⌘Q).';
  }

  @override
  String quitUiExplainedBodyWindows(int count) {
    return '$count tab vẫn chạy nền và điện thoại vẫn kết nối được. Mở lại ShellX để quay về đúng chỗ. Muốn dừng mọi shell, chọn Thoát hoàn toàn trong menu khay hệ thống.';
  }

  @override
  String get quitUiAction => 'Thoát';

  @override
  String get quitAllAction => 'Thoát hoàn toàn';

  @override
  String get confirmQuitAllAction => 'Thoát hoàn toàn';

  @override
  String get daemonOldTitle => 'Phiên nền đang chạy bản cũ';

  @override
  String daemonOldBody(String app, String old, int count) {
    return 'ShellX $app cần khởi động lại phiên nền (bản $old) đang giữ $count phiên. Khởi động lại sẽ dừng các shell đó; tab, pane, thư mục và nội dung gần nhất được mở lại. Để sau thì ShellX đóng lại, shell và điện thoại vẫn chạy với bản cũ.';
  }

  @override
  String get daemonOldRestart => 'Khởi động lại phiên nền';

  @override
  String get daemonOldLater => 'Để sau';

  @override
  String get daemonStartFailedTitle => 'Không khởi động được phiên nền';

  @override
  String get daemonStartFailedBody =>
      'ShellX cần phiên nền để chạy shell. Thử lại; nếu vẫn lỗi, khởi động lại máy hoặc cài lại ShellX.';

  @override
  String get daemonRetry => 'Thử lại';

  @override
  String get daemonRetryLabel => 'Thử khởi động lại phiên nền';

  @override
  String get daemonUnavailableEmpty => 'Đang chờ phiên nền…';

  @override
  String get daemonRestartedStrip =>
      'Phiên nền đã dừng bất ngờ và đã được khởi động lại. Các shell được mở lại ở thư mục cũ.';

  @override
  String get daemonLostStrip => 'Phiên nền đã dừng. Các shell không còn chạy.';

  @override
  String get trayBackgroundService => 'Giữ shell chạy khi đóng cửa sổ';

  @override
  String get backgroundServiceNextLaunch =>
      'Có hiệu lực ở lần mở ShellX kế tiếp.';

  @override
  String get daemonQuitFailed => 'Phiên nền chưa dừng được. Hãy thử lại.';

  @override
  String get daemonStoppingStrip => 'Đang dừng phiên nền…';

  @override
  String pasteLargeTitle(String size) {
    return 'Dán $size?';
  }

  @override
  String get pasteLargeBody =>
      'Đây là lượng văn bản lớn. Chữ được gửi từng phần và không thể hoàn tác.';

  @override
  String get pasteLargeAction => 'Dán';

  @override
  String get pasteTooLarge => 'Nội dung clipboard quá lớn để dán (hơn 16 MB)';

  @override
  String get pasteImageTooLarge => 'Ảnh lớn hơn 20 MB';

  @override
  String get pasteImageFailed => 'Không đọc được ảnh từ clipboard';

  @override
  String get pasteImageSsh => 'Không thể dán ảnh vào phiên SSH';

  @override
  String get dropHint => 'Thả để chèn đường dẫn';

  @override
  String get dropHintSsh => 'Không thể thả tệp vào phiên SSH';

  @override
  String get dropRefused => 'Tên tệp có ký tự mà shell không nhận an toàn';

  @override
  String get dropTooMany => 'Quá nhiều tệp: thả tối đa 100 tệp mỗi lần';

  @override
  String get dropSsh => 'Không thể thả tệp vào phiên SSH. Hãy dùng scp.';

  @override
  String get findPlaceholder => 'Tìm';

  @override
  String get findLabel => 'Tìm trong terminal';

  @override
  String findCount(int current, int total) {
    return '$current/$total';
  }

  @override
  String findCountCapped(int current, int total) {
    return '$current/$total+';
  }

  @override
  String get findNoMatches => 'Không có kết quả';

  @override
  String get findPrevious => 'Kết quả trước';

  @override
  String get findNext => 'Kết quả sau';

  @override
  String get findMatchCase => 'Phân biệt hoa thường';

  @override
  String get findClose => 'Đóng tìm kiếm';

  @override
  String get findMenuItem => 'Tìm…';

  @override
  String get actionStartSearch => 'Tìm trong terminal';

  @override
  String get actionSearchNext => 'Tìm kết quả sau';

  @override
  String get actionEditLineStart => 'Về đầu dòng';

  @override
  String get actionEditLineEnd => 'Về cuối dòng';

  @override
  String get actionEditLineDeleteLine => 'Xóa đến đầu dòng';

  @override
  String get actionEditLineDeleteWord => 'Xóa từ phía trước';

  @override
  String get actionEditLineDeleteWordForward => 'Xóa từ phía sau';

  @override
  String get actionSearchPrevious => 'Tìm kết quả trước';

  @override
  String get actionEndSearch => 'Đóng tìm kiếm';

  @override
  String get linkConfirmTitle => 'Mở liên kết này?';

  @override
  String linkConfirmBody(String host, String url) {
    return 'Chữ hiển thị không phải địa chỉ này. Liên kết mở:\n$host\n$url';
  }

  @override
  String get linkConfirmAction => 'Mở';

  @override
  String get linkOpenFailed => 'Không mở được liên kết';

  @override
  String get menuOpenLink => 'Mở liên kết';

  @override
  String get menuCopyLink => 'Sao chép địa chỉ liên kết';

  @override
  String get menuRevealFile => 'Hiện trong Finder';

  @override
  String get menuRevealFileWin => 'Hiện trong Explorer';

  @override
  String get actionToggleCopyMode => 'Chế độ copy';

  @override
  String get copyModeChip => 'CHẾ ĐỘ COPY';

  @override
  String get copyModeHint => 'y chép · v chọn · Esc thoát';

  @override
  String get copyModeCopied => 'Đã chép';

  @override
  String get actionReopenClosed => 'Mở lại tab đã đóng';

  @override
  String reopenedTab(String name) {
    return 'Đã mở lại “$name”';
  }

  @override
  String get reopenNothing => 'Không có gì để mở lại';

  @override
  String get actionFocusBack => 'Quay lại pane trước';

  @override
  String get actionFocusForward => 'Tới pane kế';

  @override
  String get settingsPageGeneral => 'Chung';

  @override
  String get settingsPageAppearance => 'Giao diện';

  @override
  String get settingsPageTerminal => 'Terminal';

  @override
  String get settingsPageKeys => 'Phím tắt';

  @override
  String get settingsPageAgents => 'Agent';

  @override
  String get settingsPagePhone => 'Điện thoại';

  @override
  String get settingsPageAdvanced => 'Nâng cao';

  @override
  String get settingsTheme => 'Chủ đề';

  @override
  String get settingsFontFamily => 'Font';

  @override
  String get settingsFontSize => 'Cỡ chữ';

  @override
  String get settingsFontWeight => 'Độ đậm chữ';

  @override
  String get settingsFontWeightLight => 'Nhẹ';

  @override
  String get settingsFontWeightRegular => 'Thường';

  @override
  String get settingsCellHeight => 'Chiều cao dòng';

  @override
  String get settingsPadding => 'Lề';

  @override
  String get settingsCursorStyle => 'Con trỏ';

  @override
  String get settingsCursorBlock => 'Khối';

  @override
  String get settingsCursorBar => 'Thanh';

  @override
  String get settingsCursorUnderline => 'Gạch chân';

  @override
  String get settingsCursorBlink => 'Con trỏ nhấp nháy';

  @override
  String get settingsScrollback => 'Số dòng cuộn lại';

  @override
  String get settingsWorkingDir => 'Tab mới bắt đầu ở';

  @override
  String get settingsOptionAsAlt => 'Phím Option làm Alt';

  @override
  String get settingsConfirmClose => 'Hỏi trước khi đóng';

  @override
  String get settingsConfirmCloseRunning => 'Khi có lệnh đang chạy';

  @override
  String get settingsConfirmCloseNever => 'Không bao giờ';

  @override
  String get settingsConfirmCloseAlways => 'Luôn luôn';

  @override
  String get settingsGhosttyConfig => 'Đọc font và màu từ Ghostty';

  @override
  String get settingsBackground => 'Màu nền';

  @override
  String get settingsForeground => 'Màu chữ';

  @override
  String get settingsCursorColor => 'Màu con trỏ';

  @override
  String get settingsSelectionColor => 'Màu vùng chọn';

  @override
  String get settingsTitle => 'Cài đặt';

  @override
  String get settingsSearch => 'Tìm cài đặt';

  @override
  String settingsNoMatch(String query) {
    return 'Không có cài đặt nào khớp “$query”';
  }

  @override
  String get settingsNoMatchHint => 'Không thấy? Mở tệp cấu hình.';

  @override
  String get settingsOpenFile => 'Mở tệp cấu hình';

  @override
  String get settingsReload => 'Tải lại';

  @override
  String settingsSavedInFile(String key) {
    return 'Lưu trong tệp cấu hình · $key';
  }

  @override
  String settingsSetIn(String file, int line) {
    return 'Đặt trong $file, dòng $line';
  }

  @override
  String get settingsFromGhostty =>
      'Lấy từ cấu hình Ghostty của bạn. Đổi ở đây sẽ ghi đè cho ShellX.';

  @override
  String get settingsMultiLine => 'Được đặt ở nhiều dòng. Hãy sửa trong tệp.';

  @override
  String get settingsReset => 'Về mặc định';

  @override
  String get settingsResetAll => 'Hoàn tác mọi thay đổi đã làm ở đây';

  @override
  String get settingsResetAllConfirm =>
      'Xoá các cài đặt ShellX đã ghi vào tệp cấu hình? Dòng bạn tự viết được giữ nguyên.';

  @override
  String get settingsFileChanged =>
      'Tệp đã đổi trong lúc bạn chỉnh. Đã nạp lại, hãy thử lại.';

  @override
  String get settingsFileDamaged =>
      'Khối do ShellX quản lý trong tệp bị hỏng. Hãy mở tệp để sửa.';

  @override
  String get settingsFileUnwritable => 'Không lưu được tệp';

  @override
  String get settingsPreviewLabel => 'Xem trước';

  @override
  String get settingsPreviewNote =>
      'Bản xem trước không gồm cỡ chữ riêng của workspace này.';

  @override
  String get settingsFontFamilyHint => 'Một font đã cài trên máy';

  @override
  String get settingsScrollbackNote => 'Áp dụng cho pane mở từ bây giờ.';

  @override
  String get settingsWorkingDirHome => 'Thư mục chính';

  @override
  String get settingsWorkingDirInherit => 'Thư mục của pane hiện tại';

  @override
  String get settingsWorkingDirPath => 'Một thư mục…';

  @override
  String get settingsGlobalHotkey => 'Ẩn/hiện ShellX từ mọi nơi';

  @override
  String get settingsGlobalHotkeyNone => 'Chưa đặt';

  @override
  String get settingsGlobalHotkeyRecord => 'Nhấn tổ hợp phím…';

  @override
  String get settingsGlobalHotkeyUndetected =>
      'Một số xung đột với app khác không phát hiện được.';

  @override
  String get settingsGlobalHotkeyTaken =>
      'Tổ hợp này đang được ứng dụng khác dùng';

  @override
  String get settingsOpenTour => 'Xem lại phần hướng dẫn';

  @override
  String settingsVersion(String version) {
    return 'Phiên bản $version';
  }

  @override
  String settingsProblems(int n) {
    return '$n vấn đề cấu hình';
  }

  @override
  String get settingsLoginNeeded => 'Đăng nhập để quản lý kết nối điện thoại';

  @override
  String get settingsCommandsNote =>
      'Lệnh và đoạn chữ của bạn được sửa trong tệp.';

  @override
  String get settingsConfigPath => 'Tệp cấu hình';

  @override
  String get settingsProblemsShow => 'Xem';

  @override
  String get settingsCopyPath => 'Sao chép đường dẫn';

  @override
  String settingsResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tìm thấy $count cài đặt',
      one: 'Tìm thấy 1 cài đặt',
    );
    return '$_temp0';
  }

  @override
  String get actionOpenSettings => 'Cài đặt';

  @override
  String get trayConfigSettings => 'Cài đặt…';

  @override
  String get settingsPageNavLabel => 'Các trang cài đặt';

  @override
  String get settingsThemeSearch => 'Tìm chủ đề';

  @override
  String get settingsThemeNotFound =>
      'Không đọc được tệp chủ đề. Đang dùng màu của ShellX.';

  @override
  String get settingsOptionAsAltOff => 'Tắt';

  @override
  String get settingsOptionAsAltLeft => 'Option trái';

  @override
  String get settingsOptionAsAltRight => 'Option phải';

  @override
  String get settingsOptionAsAltBoth => 'Cả hai phím Option';

  @override
  String get settingsDefaultValue => 'Mặc định';

  @override
  String get settingsHexHint => '#RRGGBB';

  @override
  String get actionSearchAll => 'Tìm trong mọi terminal';

  @override
  String get searchAllTitle => 'Tìm trong mọi terminal';

  @override
  String get searchAllFieldLabel => 'Tìm trong mọi terminal';

  @override
  String get searchAllHint => 'Tìm trong mọi terminal…';

  @override
  String get searchAllNeedTwo => 'Nhập ít nhất 2 ký tự';

  @override
  String get searchAllNone => 'Không có kết quả trong terminal nào';

  @override
  String searchAllCapped(int count) {
    return 'Hiện $count kết quả đầu tiên';
  }

  @override
  String searchAllCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kết quả',
    );
    return '$_temp0';
  }

  @override
  String searchAllPane(int n) {
    return 'Pane $n';
  }

  @override
  String searchAllLine(int n) {
    return 'Dòng $n';
  }

  @override
  String actionSwapSplit(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'left': 'Đổi chỗ với pane bên trái',
      'right': 'Đổi chỗ với pane bên phải',
      'up': 'Đổi chỗ với pane phía trên',
      'other': 'Đổi chỗ với pane phía dưới',
    });
    return '$_temp0';
  }

  @override
  String get actionBreakPane => 'Chuyển pane sang tab riêng';

  @override
  String actionJoinPane(String n) {
    return 'Chuyển pane tới tab $n';
  }

  @override
  String moveTabToWorkspace(String workspace) {
    return 'Chuyển tab tới $workspace';
  }

  @override
  String movePaneToTab(String tab) {
    return 'Chuyển pane tới tab $tab';
  }

  @override
  String get paneMoveToTabMenu => 'Chuyển pane tới tab ▸';

  @override
  String get paneMoveToTabTitle => 'Chuyển pane tới';

  @override
  String get paneSwapMenu => 'Đổi chỗ với pane bên cạnh ▸';

  @override
  String get paneSwapTitle => 'Đổi chỗ với';

  @override
  String get paneSwapLeft => 'Pane bên trái';

  @override
  String get paneSwapRight => 'Pane bên phải';

  @override
  String get paneSwapUp => 'Pane phía trên';

  @override
  String get paneSwapDown => 'Pane phía dưới';

  @override
  String get searchAllGone => 'Đã trôi khỏi lịch sử cuộn';

  @override
  String get actionTogglePinTab => 'Ghim hoặc bỏ ghim tab';

  @override
  String get tabPin => 'Ghim tab';

  @override
  String get tabUnpin => 'Bỏ ghim tab';

  @override
  String get tabPinned => 'Đã ghim';

  @override
  String get tabSetDescription => 'Đặt mô tả…';

  @override
  String get tabDescriptionPlaceholder => 'Mô tả tab';

  @override
  String get tabStatusMenu => 'Trạng thái';

  @override
  String get tabStatusNone => 'Không có trạng thái';

  @override
  String get tabStatusInProgress => 'Đang làm';

  @override
  String get tabStatusReview => 'Chờ duyệt';

  @override
  String get tabStatusBlocked => 'Bị chặn';

  @override
  String get tabStatusDone => 'Xong';

  @override
  String tabStatusLabel(String status) {
    return 'Trạng thái: $status';
  }

  @override
  String get tabPinnedCloseTitle => 'Đóng tab đã ghim?';

  @override
  String tabPinnedCloseBody(String name) {
    return '“$name” đã được ghim.';
  }

  @override
  String get actionWorkspaceFontBigger => 'Tăng cỡ chữ trong workspace này';

  @override
  String get actionWorkspaceFontSmaller => 'Giảm cỡ chữ trong workspace này';

  @override
  String get actionWorkspaceFontReset => 'Đặt lại cỡ chữ trong workspace này';

  @override
  String workspaceZoomTip(String step) {
    return 'Cỡ chữ $step';
  }

  @override
  String get actionShowTour => 'Xem hướng dẫn';

  @override
  String get actionShowWhatsNew => 'Có gì mới';

  @override
  String get tourSkip => 'Bỏ qua';

  @override
  String get tourNext => 'Tiếp';

  @override
  String get tourBack => 'Quay lại';

  @override
  String get tourDone => 'Xong';

  @override
  String tourStep(int n, int total) {
    return '$n/$total';
  }

  @override
  String get tourLabel => 'Hướng dẫn ShellX';

  @override
  String get tourTabsTitle => 'Tab và pane';

  @override
  String tourTabsBody(String newTab, String splitRight, String splitDown) {
    return 'Mở tab bằng $newTab. Chia pane bằng $splitRight hoặc $splitDown.';
  }

  @override
  String get tourNotifyTitle => 'Biết khi nào agent cần bạn';

  @override
  String tourNotifyBody(String jumpUnread) {
    return 'Một vòng sáng hiện ở pane. Nhảy tới đó bằng $jumpUnread.';
  }

  @override
  String get tourFindTitle => 'Tìm đường nhanh';

  @override
  String tourFindBody(String find, String searchAll, String palette) {
    return 'Tìm chữ bằng $find, trong mọi terminal bằng $searchAll, và chạy mọi lệnh từ $palette.';
  }

  @override
  String get tourSettingsTitle => 'Chỉnh theo ý bạn';

  @override
  String tourSettingsBody(String settings) {
    return 'Mở Cài đặt bằng $settings. Mọi thứ cũng nằm trong một tệp văn bản thường.';
  }

  @override
  String whatsNewTitle(String version) {
    return 'Có gì mới ở bản $version';
  }

  @override
  String get whatsNewDone => 'Đã hiểu';

  @override
  String get whatsNewMore => 'Xem mọi thay đổi';

  @override
  String emptyHintNewTab(String shortcut) {
    return '$shortcut Tab mới';
  }

  @override
  String emptyHintPalette(String shortcut) {
    return '$shortcut Bảng lệnh';
  }

  @override
  String emptyHintSettings(String shortcut) {
    return '$shortcut Cài đặt';
  }

  @override
  String get notificationsEmptyTitle => 'Chưa có thông báo';

  @override
  String get notificationsEmptyBody =>
      'Một vòng sáng hiện ở pane khi agent cần bạn.';

  @override
  String get agentStateRunning => 'Đang chạy';

  @override
  String get agentStateNeedsInput => 'Cần bạn trả lời';

  @override
  String get agentStateIdle => 'Đang chờ';

  @override
  String get agentStateDone => 'Xong';

  @override
  String agentStatusTooltip(String agent, String state) {
    return '$agent: $state';
  }

  @override
  String agentStatusAnnounce(String agent) {
    return '$agent cần bạn trả lời';
  }

  @override
  String agentNotifyNeedsInput(String agent) {
    return '$agent cần bạn trả lời';
  }

  @override
  String agentNotifyDone(String agent) {
    return '$agent đã xong';
  }

  @override
  String get agentNamesClaude => 'Claude Code';

  @override
  String get agentNamesCodex => 'Codex';

  @override
  String get agentNamesGemini => 'Gemini CLI';

  @override
  String get agentNamesOpencode => 'OpenCode';

  @override
  String resumeBannerText(String agent) {
    return '$agent đang chạy ở đây trước khi ShellX khởi động lại.';
  }

  @override
  String get resumeBannerResume => 'Tiếp tục phiên';

  @override
  String get resumeBannerDismiss => 'Bỏ qua';

  @override
  String resumeBannerTooltip(String command) {
    return 'Gõ “$command” vào terminal này rồi nhấn Enter.';
  }

  @override
  String get settingAgentResume => 'Đề nghị tiếp tục phiên agent';

  @override
  String get settingAgentResumeDesc =>
      'Sau khi khởi động lại, hiện nút để tiếp tục agent bạn đang dùng. Không có gì chạy cho tới khi bạn bấm.';

  @override
  String get settingAgentResumeAsk => 'Hỏi';

  @override
  String get settingAgentResumeOff => 'Tắt';

  @override
  String get settingsAgentIntegrations => 'Tích hợp agent';

  @override
  String get settingsAgentIntegrationsHint =>
      'Hook giúp ShellX biết agent đang chạy hay đang chờ bạn. Cài đặt luôn hiện từng thay đổi và hỏi trước.';

  @override
  String get integrationInstalled => 'Đã cài';

  @override
  String get integrationNotInstalled => 'Chưa cài';

  @override
  String integrationNotFound(String agent) {
    return 'Không thấy $agent trên máy này';
  }

  @override
  String get integrationSetUp => 'Cài đặt trong terminal';

  @override
  String get integrationRemove => 'Gỡ trong terminal';

  @override
  String get integrationLimit =>
      'Codex chỉ báo khi một lượt kết thúc, không báo “đang chạy”.';

  @override
  String get resumeBannerBusy => 'Đang chờ shell…';

  @override
  String get integrationNeedsCli =>
      'Hãy cài lệnh shellx trước (Cài đặt › Dòng lệnh)';

  @override
  String get settingPrStatus => 'Hiện trạng thái pull request';

  @override
  String get settingPrStatusDesc =>
      'Dùng GitHub CLI (gh) đã đăng nhập sẵn trên máy. ShellX không bao giờ đọc token của bạn.';

  @override
  String get settingPrStatusNoGh => 'Không tìm thấy GitHub CLI (gh).';

  @override
  String get prOpen => 'đang mở';

  @override
  String get prDraft => 'nháp';

  @override
  String get prMerged => 'đã merge';

  @override
  String get prClosed => 'đã đóng';

  @override
  String get prChecksPassing => 'CI đạt';

  @override
  String get prChecksFailing => 'CI lỗi';

  @override
  String get prChecksPending => 'CI đang chạy';

  @override
  String get prChecksNone => 'không có CI';

  @override
  String get prReviewApproved => 'đã duyệt';

  @override
  String get prReviewChanges => 'cần sửa';

  @override
  String prTooltip(int number, String state, String checks) {
    return 'Pull request #$number: $state, $checks';
  }

  @override
  String get prOpenInBrowser => 'Mở trong trình duyệt';

  @override
  String tabOpenPr(int number) {
    return 'Mở pull request #$number';
  }

  @override
  String get settingAgentCommand => 'Chạy lệnh khi agent có sự kiện';

  @override
  String get settingAgentCommandDesc =>
      'Đặt agent-event-command trong tệp cấu hình. ShellX hỏi trước khi chạy một lệnh mới.';

  @override
  String get agentCommandApproveTitle => 'Cho phép lệnh này?';

  @override
  String get agentCommandApproveBody =>
      'ShellX sẽ chạy lệnh này khi agent bắt đầu, cần nhập hoặc xong. Lệnh không có quyền gì với phiên ShellX của bạn.';

  @override
  String get agentCommandApproveAllow => 'Cho phép';

  @override
  String get agentCommandApproveCancel => 'Huỷ';

  @override
  String get agentCommandNotApproved =>
      'Đã đặt lệnh sự kiện agent nhưng chưa được cho phép.';

  @override
  String get agentCommandReview => 'Xem';

  @override
  String get agentCommandFailed => 'Lệnh sự kiện agent không chạy được.';

  @override
  String get configProblemAgentCommandMainOnly =>
      'agent-event-command chỉ được đọc từ tệp cấu hình ShellX chính';

  @override
  String get settingLanguage => 'Ngôn ngữ';

  @override
  String get settingLanguageSystem => 'Theo hệ thống';

  @override
  String get settingLanguageEn => 'English';

  @override
  String get settingLanguageVi => 'Tiếng Việt';

  @override
  String get settingLanguageRestart =>
      'Có hiệu lực sau khi bạn khởi động lại ShellX.';
}
