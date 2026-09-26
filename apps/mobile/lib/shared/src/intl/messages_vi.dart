// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a vi locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'vi';

  static String m0(email) => "Xóa tài khoản ${email}, mọi máy và mọi ghép nối.";

  static String m1(site) =>
      "Cài ShellX trên máy tính (macOS hoặc Windows) từ ${site}.";

  static String m2(menu) => "Bấm biểu tượng ShellX → ${menu}, rồi quét mã.";

  static String m3(reason) => "Không mở được shell: ${reason}";

  static String m4(code) => "Đã có lỗi xảy ra (${code}).";

  static String m5(day, month, time) => "${day}/${month}, ${time}";

  static String m6(count) =>
      "${Intl.plural(count, other: '${count} phút trước')}";

  static String m7(time) => "hôm nay, ${time}";

  static String m8(time) => "hôm qua, ${time}";

  static String m9(method) => "Mở khóa bằng ${method}";

  static String m10(when) => "Lần cuối online: ${when}";

  static String m11(count) => "${Intl.plural(count, other: '${count} tab')}";

  static String m12(name) =>
      "${name} đã tin cậy điện thoại này. Từ giờ chỉ cần chạm vào máy để mở terminal.";

  static String m13(count) =>
      "${Intl.plural(count, other: 'Còn thiếu ${count} ký tự.')}";

  static String m14(count) =>
      "${Intl.plural(count, other: 'Thừa ${count} ký tự.')}";

  static String m15(when) => "mở ${when}";

  static String m16(count) =>
      "${Intl.plural(count, other: 'Máy này đang có ${count} phiên')}";

  static String m17(menu) =>
      "macOS: bấm biểu tượng ShellX trên thanh menu. Windows: bấm biểu tượng ở khay hệ thống. Chọn ${menu}";

  static String m18(code) =>
      "Lệnh cuối thoát với mã ${code}. Nội dung ở trên vẫn đọc và copy được.";

  static String m19(method) => "Khóa bằng ${method}";

  static String m20(name) =>
      "Bỏ ghép nối ${name}? Bạn sẽ phải quét lại mã QR để dùng máy này.";

  static String m21(version, build) => "ShellX ${version} (${build})";

  static String m22(terms, privacy) =>
      "Khi tạo tài khoản, bạn đồng ý với ${terms} và ${privacy}.";

  static String m23(length) => "Mật khẩu phải có ít nhất ${length} ký tự";

  static String m24(length) => "Tối đa ${length} ký tự";

  static String m25(length) => "Phải có ít nhất ${length} ký tự";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "actionCancel": MessageLookupByLibrary.simpleMessage("Hủy"),
    "actionClose": MessageLookupByLibrary.simpleMessage("Đóng"),
    "actionLater": MessageLookupByLibrary.simpleMessage("Để sau"),
    "actionScanCode": MessageLookupByLibrary.simpleMessage("Quét mã"),
    "appTitle": MessageLookupByLibrary.simpleMessage("ShellX"),
    "backToMachines": MessageLookupByLibrary.simpleMessage("Về danh sách máy"),
    "bannerReconnectButton": MessageLookupByLibrary.simpleMessage(
      "Kết nối lại",
    ),
    "bannerReconnecting": MessageLookupByLibrary.simpleMessage(
      "Mất kết nối, đang thử lại…",
    ),
    "bannerReplaced": MessageLookupByLibrary.simpleMessage(
      "Một phiên bản khác của app đã kết nối.",
    ),
    "biometricFaceId": MessageLookupByLibrary.simpleMessage("Face ID"),
    "biometricFingerprint": MessageLookupByLibrary.simpleMessage("vân tay"),
    "biometricGeneric": MessageLookupByLibrary.simpleMessage("sinh trắc học"),
    "biometricPasscode": MessageLookupByLibrary.simpleMessage("mã máy"),
    "biometricTouchId": MessageLookupByLibrary.simpleMessage("Touch ID"),
    "closeTab": MessageLookupByLibrary.simpleMessage("Đóng tab"),
    "copied": MessageLookupByLibrary.simpleMessage("Đã sao chép"),
    "copyAction": MessageLookupByLibrary.simpleMessage("Sao chép"),
    "createAccountLink": MessageLookupByLibrary.simpleMessage("Tạo tài khoản"),
    "deleteAccountButton": MessageLookupByLibrary.simpleMessage(
      "Xóa vĩnh viễn",
    ),
    "deleteAccountLoseAccount": m0,
    "deleteAccountLoseComputers": MessageLookupByLibrary.simpleMessage(
      "Mọi máy tính đang đăng nhập sẽ bị đăng xuất.",
    ),
    "deleteAccountLoseSessions": MessageLookupByLibrary.simpleMessage(
      "Phiên terminal đang mở sẽ đóng.",
    ),
    "deleteAccountPasswordLabel": MessageLookupByLibrary.simpleMessage(
      "Nhập mật khẩu để xác nhận",
    ),
    "deleteAccountTitle": MessageLookupByLibrary.simpleMessage("Xóa tài khoản"),
    "deleteAccountWarningTitle": MessageLookupByLibrary.simpleMessage(
      "Không hoàn tác được",
    ),
    "emailHint": MessageLookupByLibrary.simpleMessage("email@example.com"),
    "emailLabel": MessageLookupByLibrary.simpleMessage("Email"),
    "emptyStep1": m1,
    "emptyStep2": MessageLookupByLibrary.simpleMessage(
      "Đăng nhập cùng tài khoản này.",
    ),
    "emptyStep3": m2,
    "emptyTitle": MessageLookupByLibrary.simpleMessage("Chưa có máy nào"),
    "errorAgentOffline": MessageLookupByLibrary.simpleMessage(
      "Máy tính đang offline. Hãy mở ShellX trên máy tính rồi thử lại.",
    ),
    "errorDisposableEmail": MessageLookupByLibrary.simpleMessage(
      "Email tạm thời không dùng được. Hãy dùng email thật.",
    ),
    "errorEmailTaken": MessageLookupByLibrary.simpleMessage(
      "Email này đã được đăng ký.",
    ),
    "errorInvalidCredentials": MessageLookupByLibrary.simpleMessage(
      "Email hoặc mật khẩu không đúng.",
    ),
    "errorInvalidEmail": MessageLookupByLibrary.simpleMessage(
      "Email không hợp lệ.",
    ),
    "errorNetwork": MessageLookupByLibrary.simpleMessage(
      "Không kết nối được máy chủ. Hãy kiểm tra mạng rồi thử lại.",
    ),
    "errorNotInAccount": MessageLookupByLibrary.simpleMessage(
      "Máy này không thuộc tài khoản của bạn. Hãy đăng nhập cùng tài khoản trên máy tính.",
    ),
    "errorQrInvalid": MessageLookupByLibrary.simpleMessage(
      "Mã QR không hợp lệ hoặc đã hết hạn. Hãy tạo mã mới trên máy tính.",
    ),
    "errorRateLimited": MessageLookupByLibrary.simpleMessage(
      "Thử lại sau ít phút.",
    ),
    "errorSessionLimit": MessageLookupByLibrary.simpleMessage(
      "Máy đã mở tối đa 10 phiên. Hãy đóng bớt phiên.",
    ),
    "errorSpawnFailed": m3,
    "errorTimeout": MessageLookupByLibrary.simpleMessage(
      "Máy tính không phản hồi. Hãy thử lại.",
    ),
    "errorUnknown": m4,
    "errorUntrusted": MessageLookupByLibrary.simpleMessage(
      "Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.",
    ),
    "errorWeakPassword": MessageLookupByLibrary.simpleMessage(
      "Mật khẩu phải có 8–128 ký tự.",
    ),
    "errorWrongPassword": MessageLookupByLibrary.simpleMessage(
      "Mật khẩu không đúng.",
    ),
    "fontSizeTooltip": MessageLookupByLibrary.simpleMessage("Cỡ chữ"),
    "forbiddenTitle": MessageLookupByLibrary.simpleMessage(
      "Bạn không có quyền dùng chức năng này",
    ),
    "forgotPasswordHint": MessageLookupByLibrary.simpleMessage(
      "Quên mật khẩu? Đổi mật khẩu trong ShellX trên máy tính đang đăng nhập.",
    ),
    "keyArrowDown": MessageLookupByLibrary.simpleMessage("Mũi tên xuống"),
    "keyArrowLeft": MessageLookupByLibrary.simpleMessage("Mũi tên trái"),
    "keyArrowRight": MessageLookupByLibrary.simpleMessage("Mũi tên phải"),
    "keyArrowUp": MessageLookupByLibrary.simpleMessage("Mũi tên lên"),
    "keyMinus": MessageLookupByLibrary.simpleMessage("Dấu gạch ngang"),
    "keyPaste": MessageLookupByLibrary.simpleMessage("Dán"),
    "keyPipe": MessageLookupByLibrary.simpleMessage("Dấu gạch đứng"),
    "keySlash": MessageLookupByLibrary.simpleMessage("Dấu gạch chéo"),
    "keyTilde": MessageLookupByLibrary.simpleMessage("Dấu ngã"),
    "keyboardTooltip": MessageLookupByLibrary.simpleMessage("Bàn phím"),
    "lastSeenDate": m5,
    "lastSeenJustNow": MessageLookupByLibrary.simpleMessage("vừa xong"),
    "lastSeenMinutes": m6,
    "lastSeenToday": m7,
    "lastSeenUnknown": MessageLookupByLibrary.simpleMessage("không rõ"),
    "lastSeenYesterday": m8,
    "loadMoreFailPleaseTryAgain": MessageLookupByLibrary.simpleMessage(
      "Tải thêm thất bại\nHãy thử lại",
    ),
    "lockReason": MessageLookupByLibrary.simpleMessage("Mở khóa ShellX"),
    "lockSubtitle": MessageLookupByLibrary.simpleMessage(
      "Mở khóa để xem các máy và phiên terminal của bạn.",
    ),
    "lockTitle": MessageLookupByLibrary.simpleMessage("ShellX đang khóa"),
    "lockUnlockWith": m9,
    "loginButton": MessageLookupByLibrary.simpleMessage("Đăng nhập"),
    "loginSubtitle": MessageLookupByLibrary.simpleMessage(
      "Dùng cùng tài khoản với ShellX trên máy tính.",
    ),
    "loginTitle": MessageLookupByLibrary.simpleMessage("Đăng nhập"),
    "machineLastOnline": m10,
    "machineNotPaired": MessageLookupByLibrary.simpleMessage("Chưa ghép nối"),
    "machineOffline": MessageLookupByLibrary.simpleMessage("Máy đang offline."),
    "machineOnline": MessageLookupByLibrary.simpleMessage("Online"),
    "machineTabs": m11,
    "machineWaiting": MessageLookupByLibrary.simpleMessage("Đang chờ kết nối"),
    "machinesOfflineHeader": MessageLookupByLibrary.simpleMessage("Offline"),
    "machinesTitle": MessageLookupByLibrary.simpleMessage("Máy của bạn"),
    "networkError": MessageLookupByLibrary.simpleMessage("Lỗi mạng"),
    "noAccountPrompt": MessageLookupByLibrary.simpleMessage(
      "Chưa có tài khoản?",
    ),
    "notFound": MessageLookupByLibrary.simpleMessage("Không tìm thấy"),
    "openAppStore": MessageLookupByLibrary.simpleMessage("Mở App Store"),
    "openPlayStore": MessageLookupByLibrary.simpleMessage("Mở Google Play"),
    "openSettings": MessageLookupByLibrary.simpleMessage("Mở Cài đặt"),
    "openTerminal": MessageLookupByLibrary.simpleMessage("Mở terminal"),
    "pairNewMachine": MessageLookupByLibrary.simpleMessage("Ghép nối máy mới"),
    "pairPhoneMenuItem": MessageLookupByLibrary.simpleMessage(
      "Ghép nối điện thoại…",
    ),
    "pairingFailedTitle": MessageLookupByLibrary.simpleMessage(
      "Không ghép nối được",
    ),
    "pairingSucceeded": MessageLookupByLibrary.simpleMessage("Đã ghép nối"),
    "pairingSucceededBody": m12,
    "passwordHide": MessageLookupByLibrary.simpleMessage("Ẩn mật khẩu"),
    "passwordHint": MessageLookupByLibrary.simpleMessage("Mật khẩu"),
    "passwordLabel": MessageLookupByLibrary.simpleMessage("Mật khẩu"),
    "passwordMissing": m13,
    "passwordRule": MessageLookupByLibrary.simpleMessage("Từ 8 đến 128 ký tự."),
    "passwordShow": MessageLookupByLibrary.simpleMessage("Hiện mật khẩu"),
    "passwordTooLong": m14,
    "pickerAttachedElsewhere": MessageLookupByLibrary.simpleMessage(
      "đang mở trên thiết bị khác",
    ),
    "pickerOpen": MessageLookupByLibrary.simpleMessage("Mở"),
    "pickerStarted": m15,
    "pickerSubtitle": MessageLookupByLibrary.simpleMessage(
      "Mở lại phiên cũ để xem tiếp đúng chỗ đã dừng, hoặc tạo phiên mới.",
    ),
    "pickerTitle": m16,
    "privacyLink": MessageLookupByLibrary.simpleMessage(
      "Chính sách quyền riêng tư",
    ),
    "registerButton": MessageLookupByLibrary.simpleMessage("Tạo tài khoản"),
    "registerSubtitle": MessageLookupByLibrary.simpleMessage(
      "Một tài khoản cho điện thoại và mọi máy tính của bạn.",
    ),
    "registerTitle": MessageLookupByLibrary.simpleMessage("Tạo tài khoản"),
    "retry": MessageLookupByLibrary.simpleMessage("Thử lại"),
    "scanAgain": MessageLookupByLibrary.simpleMessage("Quét lại"),
    "scanQrButton": MessageLookupByLibrary.simpleMessage("Quét mã QR"),
    "scannerCameraDenied": MessageLookupByLibrary.simpleMessage(
      "Cần quyền camera để quét mã QR. Hãy cho phép trong Cài đặt của điện thoại.",
    ),
    "scannerCameraError": MessageLookupByLibrary.simpleMessage(
      "Không mở được camera.",
    ),
    "scannerCardBody": m17,
    "scannerCardTitle": MessageLookupByLibrary.simpleMessage(
      "Mã nằm trên máy tính của bạn",
    ),
    "scannerPairing": MessageLookupByLibrary.simpleMessage("Đang ghép nối…"),
    "scannerTitle": MessageLookupByLibrary.simpleMessage("Quét mã ghép nối"),
    "sessionEnded": MessageLookupByLibrary.simpleMessage("Phiên đã kết thúc"),
    "sessionExitedBody": m18,
    "sessionGoneBody": MessageLookupByLibrary.simpleMessage(
      "Máy tính không còn phiên này. Nội dung ở trên vẫn đọc và copy được.",
    ),
    "sessionsLoading": MessageLookupByLibrary.simpleMessage(
      "Đang lấy danh sách phiên…",
    ),
    "settingsAccountGroup": MessageLookupByLibrary.simpleMessage("Tài khoản"),
    "settingsBiometricUnavailable": MessageLookupByLibrary.simpleMessage(
      "Thiết bị chưa đặt mã khóa hoặc sinh trắc học",
    ),
    "settingsDeleteAccount": MessageLookupByLibrary.simpleMessage(
      "Xóa tài khoản",
    ),
    "settingsEmail": MessageLookupByLibrary.simpleMessage("Email"),
    "settingsFontSize": MessageLookupByLibrary.simpleMessage("Cỡ chữ mặc định"),
    "settingsLockFootnote": MessageLookupByLibrary.simpleMessage(
      "Hỏi khi mở app và khi quay lại sau hơn 5 phút.",
    ),
    "settingsLockWith": m19,
    "settingsLogout": MessageLookupByLibrary.simpleMessage("Đăng xuất"),
    "settingsLogoutConfirm": MessageLookupByLibrary.simpleMessage(
      "Đăng xuất khỏi ShellX? Các máy đã ghép nối vẫn được giữ cho lần đăng nhập sau.",
    ),
    "settingsNoPairedMachines": MessageLookupByLibrary.simpleMessage(
      "Chưa ghép nối máy nào.",
    ),
    "settingsPairedMachines": MessageLookupByLibrary.simpleMessage(
      "Máy đã ghép nối",
    ),
    "settingsSecurityGroup": MessageLookupByLibrary.simpleMessage("Bảo mật"),
    "settingsTerminalGroup": MessageLookupByLibrary.simpleMessage("Terminal"),
    "settingsTitle": MessageLookupByLibrary.simpleMessage("Cài đặt"),
    "settingsTooltip": MessageLookupByLibrary.simpleMessage("Cài đặt"),
    "settingsUnpair": MessageLookupByLibrary.simpleMessage("Bỏ ghép nối"),
    "settingsUnpairConfirm": m20,
    "settingsUnpairFailed": MessageLookupByLibrary.simpleMessage(
      "Chưa bỏ ghép nối được.",
    ),
    "settingsVersion": m21,
    "signedOutAccountDeleted": MessageLookupByLibrary.simpleMessage(
      "Tài khoản đã được xóa.",
    ),
    "signedOutExpired": MessageLookupByLibrary.simpleMessage(
      "Phiên đăng nhập đã hết hiệu lực. Hãy đăng nhập lại.",
    ),
    "somethingWentWrong": MessageLookupByLibrary.simpleMessage(
      "Đã có lỗi xảy ra",
    ),
    "somethingWentWrongPleaseTryAgain": MessageLookupByLibrary.simpleMessage(
      "Đã có lỗi xảy ra, hãy thử lại",
    ),
    "tabClosedByHost": MessageLookupByLibrary.simpleMessage(
      "Phiên đã bị đóng trên máy tính.",
    ),
    "tabReattach": MessageLookupByLibrary.simpleMessage("Gắn lại"),
    "tabTakenOver": MessageLookupByLibrary.simpleMessage(
      "Phiên đang được mở trên thiết bị khác.",
    ),
    "terminalCloseConfirm": MessageLookupByLibrary.simpleMessage(
      "Đóng phiên này? Mọi chương trình đang chạy trong phiên sẽ bị dừng.",
    ),
    "terminalCloseTab": MessageLookupByLibrary.simpleMessage("Đóng phiên"),
    "terminalConnected": MessageLookupByLibrary.simpleMessage(
      "Đã kết nối · mã hóa đầu cuối",
    ),
    "terminalConnecting": MessageLookupByLibrary.simpleMessage("Đang kết nối…"),
    "terminalFailedTabTitle": MessageLookupByLibrary.simpleMessage("shell"),
    "terminalNoTabs": MessageLookupByLibrary.simpleMessage(
      "Chưa có phiên nào đang mở.",
    ),
    "terminalOpenNew": MessageLookupByLibrary.simpleMessage("Mở phiên mới"),
    "termsLink": MessageLookupByLibrary.simpleMessage("Điều khoản"),
    "termsNotice": m22,
    "unauthorized": MessageLookupByLibrary.simpleMessage("Chưa được xác thực"),
    "unknownError": MessageLookupByLibrary.simpleMessage("Lỗi không xác định"),
    "unknownMachine": MessageLookupByLibrary.simpleMessage(
      "Máy không xác định",
    ),
    "untrustedTitle": MessageLookupByLibrary.simpleMessage("Cần ghép nối lại"),
    "updateRequiredBody": MessageLookupByLibrary.simpleMessage(
      "Phiên bản này không còn kết nối được với máy của bạn. Cập nhật để dùng tiếp.",
    ),
    "updateRequiredTitle": MessageLookupByLibrary.simpleMessage(
      "Cần cập nhật app",
    ),
    "validationEmailInvalid": MessageLookupByLibrary.simpleMessage(
      "Hãy nhập địa chỉ email hợp lệ",
    ),
    "validationEmailRequired": MessageLookupByLibrary.simpleMessage(
      "Cần nhập email",
    ),
    "validationPasswordConfirmRequired": MessageLookupByLibrary.simpleMessage(
      "Hãy xác nhận mật khẩu",
    ),
    "validationPasswordDigit": MessageLookupByLibrary.simpleMessage(
      "Mật khẩu phải có ít nhất một chữ số",
    ),
    "validationPasswordLowercase": MessageLookupByLibrary.simpleMessage(
      "Mật khẩu phải có ít nhất một chữ thường",
    ),
    "validationPasswordMinLength": m23,
    "validationPasswordNotMatch": MessageLookupByLibrary.simpleMessage(
      "Mật khẩu không khớp",
    ),
    "validationPasswordRequired": MessageLookupByLibrary.simpleMessage(
      "Cần nhập mật khẩu",
    ),
    "validationPasswordSpecialChar": MessageLookupByLibrary.simpleMessage(
      "Mật khẩu phải có ít nhất một ký tự đặc biệt",
    ),
    "validationPasswordUppercase": MessageLookupByLibrary.simpleMessage(
      "Mật khẩu phải có ít nhất một chữ hoa",
    ),
    "validationPhoneInvalid": MessageLookupByLibrary.simpleMessage(
      "Hãy nhập số điện thoại hợp lệ",
    ),
    "validationPhoneRequired": MessageLookupByLibrary.simpleMessage(
      "Cần nhập số điện thoại",
    ),
    "validationTextMaxLength": m24,
    "validationTextMinLength": m25,
    "validationTextRequired": MessageLookupByLibrary.simpleMessage(
      "Trường này là bắt buộc",
    ),
  };
}
