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

  static String m0(agent) => "${agent} hỏi bạn";

  static String m1(agent) => "Nhắn cho ${agent}…";

  static String m2(percent) => "Ngữ cảnh ${percent}%";

  static String m3(count) => "${count} dòng; phần giữa xem trên máy tính";

  static String m4(count) => "+${count} tệp nữa";

  static String m5(agent, code) => "${agent} dừng bất ngờ (mã thoát ${code}).";

  static String m6(agent) => "${agent} gửi dữ liệu ShellX không đọc được nên đã bị dừng.";

  static String m7(agent) => "${agent} cần đăng nhập, trên máy tính.";

  static String m8(agent) => "Không tìm thấy ${agent} trên máy tính.";

  static String m9(agent, version) => "${agent} cần máy tính có Node.js ${version} trở lên.";

  static String m10(agent) => "${agent} chưa được cài trên máy tính.";

  static String m11(agent) => "${agent} không khởi động được.";

  static String m12(reason) => "Hoàn tác đang tắt cho dự án này (${reason}).";

  static String m13(reason) => "Hoàn tác đang tắt cho lượt này (${reason}).";

  static String m14(count) => "còn ${count} yêu cầu";

  static String m15(agent) => "${agent} xin quyền:";

  static String m16(done, total) => "Kế hoạch · ${done}/${total}";

  static String m17(reason) => "Máy tính không nhận (${reason}).";

  static String m18(agent, state) => "${agent} · ${state}";

  static String m19(max) => "Quá dài để gửi từ điện thoại (tối đa ${max} KB).";

  static String m20(target) => "Tạo ${target}";

  static String m21(target) => "Xóa ${target}";

  static String m22(target) => "Sửa ${target}";

  static String m23(target) => "Chạy ${target}";

  static String m24(target) => "Tải ${target}";

  static String m25(target) => "Đổi tên ${target}";

  static String m26(target) => "Đọc ${target}";

  static String m27(time) => "đang chạy · ${time}";

  static String m28(target) => "Tìm ${target}";

  static String m29(n) => "Lượt ${n} lỗi";

  static String m30(count) => "${Intl.plural(count, other: '${count} tệp đổi')}";

  static String m31(n) => "Lượt ${n} bị gián đoạn";

  static String m32(n, time) => "Đã dừng lượt ${n} · ${time}";

  static String m33(n, time) => "Lượt ${n} · ${time}";

  static String m34(option) => "Bạn chọn: ${option}";

  static String m35(email) => "Xóa tài khoản ${email}, mọi máy và mọi ghép nối.";

  static String m36(site) => "Cài ShellX trên máy tính (macOS hoặc Windows) từ ${site}.";

  static String m37(menu) => "Bấm biểu tượng ShellX, chọn ${menu}, rồi quét mã.";

  static String m38(reason) => "Không mở được shell: ${reason}";

  static String m39(code) => "Đã có lỗi xảy ra (${code}).";

  static String m40(day, month, time) => "${day}/${month}, ${time}";

  static String m41(count) => "${Intl.plural(count, other: '${count} phút trước')}";

  static String m42(time) => "hôm nay, ${time}";

  static String m43(time) => "hôm qua, ${time}";

  static String m44(method) => "Mở khóa bằng ${method}";

  static String m45(when) => "Lần cuối online: ${when}";

  static String m46(count) => "${Intl.plural(count, other: '${count} tab')}";

  static String m47(tabs, unseen) => "${tabs} tab · ${unseen} có chữ mới";

  static String m48(name) => "${name} đã tin cậy điện thoại này. Từ giờ chỉ cần chạm vào máy để mở terminal.";

  static String m49(count) => "${Intl.plural(count, other: 'Còn thiếu ${count} ký tự.')}";

  static String m50(count) => "${Intl.plural(count, other: 'Thừa ${count} ký tự.')}";

  static String m51(name) => "${name} · xong";

  static String m52(name) => "${name} · đang chờ";

  static String m53(name) => "${name} · cần bạn trả lời";

  static String m54(name) => "${name} · đang chạy";

  static String m55(when) => "mở ${when}";

  static String m56(count) => "${Intl.plural(count, other: 'Máy này đang có ${count} phiên')}";

  static String m57(number) => "Lựa chọn ${number}";

  static String m58(menu) =>
      "macOS: bấm biểu tượng ShellX trên thanh menu. Windows: bấm biểu tượng ở khay hệ thống. Chọn ${menu}";

  static String m59(code) => "Lệnh cuối thoát với mã ${code}. Nội dung ở trên vẫn đọc và copy được.";

  static String m60(method) => "Khóa bằng ${method}";

  static String m61(name) => "Bỏ ghép nối ${name}? Bạn sẽ phải quét lại mã QR để dùng máy này.";

  static String m62(version, build) => "ShellX ${version} (${build})";

  static String m63(terms, privacy) => "Khi tạo tài khoản, bạn đồng ý với ${terms} và ${privacy}.";

  static String m64(length) => "Mật khẩu phải có ít nhất ${length} ký tự.";

  static String m65(length) => "Tối đa ${length} ký tự.";

  static String m66(length) => "Phải có ít nhất ${length} ký tự.";

  static String m67(lines) => "Hiển thị ${lines} dòng cuối";

  static String m68(target) => "Gửi tới: ${target}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "actionCancel": MessageLookupByLibrary.simpleMessage("Hủy"),
    "actionClose": MessageLookupByLibrary.simpleMessage("Đóng"),
    "actionLater": MessageLookupByLibrary.simpleMessage("Để sau"),
    "actionScanCode": MessageLookupByLibrary.simpleMessage("Quét mã"),
    "agentDotNeedsInput": MessageLookupByLibrary.simpleMessage(
      "Agent cần bạn trả lời",
    ),
    "agentDotRunning": MessageLookupByLibrary.simpleMessage("Agent đang chạy"),
    "aiAgentNotReady": MessageLookupByLibrary.simpleMessage(
      "cài trên máy tính",
    ),
    "aiAnsweredElsewhere": MessageLookupByLibrary.simpleMessage(
      "Đã được trả lời ở thiết bị khác.",
    ),
    "aiAskAnswered": MessageLookupByLibrary.simpleMessage("Đã trả lời"),
    "aiAskCancelled": MessageLookupByLibrary.simpleMessage("Đã hủy"),
    "aiAskDecline": MessageLookupByLibrary.simpleMessage("Từ chối"),
    "aiAskDeclined": MessageLookupByLibrary.simpleMessage("Đã từ chối"),
    "aiAskOnComputer": MessageLookupByLibrary.simpleMessage(
      "Trả lời câu hỏi này trên máy tính.",
    ),
    "aiAskSubmit": MessageLookupByLibrary.simpleMessage("Gửi câu trả lời"),
    "aiAskTitle": m0,
    "aiAskUnsupported": MessageLookupByLibrary.simpleMessage(
      "Câu hỏi này dùng kiểu trả lời ShellX chưa hỗ trợ.",
    ),
    "aiAskWaiting": MessageLookupByLibrary.simpleMessage(
      "Chờ bạn trả lời ở dưới",
    ),
    "aiBusy": MessageLookupByLibrary.simpleMessage(
      "Quá nhiều yêu cầu cùng lúc. Chờ một lát rồi thử lại.",
    ),
    "aiChromeTooltip": MessageLookupByLibrary.simpleMessage("Phiên AI"),
    "aiClosedDesktop": MessageLookupByLibrary.simpleMessage(
      "ShellX trên máy tính đã thoát. Mở ShellX trên máy tính rồi mở lại phiên.",
    ),
    "aiClosedGone": MessageLookupByLibrary.simpleMessage(
      "Phiên AI này đã đóng trên máy tính.",
    ),
    "aiClosedUnreadable": MessageLookupByLibrary.simpleMessage(
      "Điện thoại không đọc được phiên AI này. Xem trên máy tính.",
    ),
    "aiComposerHint": m1,
    "aiContext": m2,
    "aiCreated": MessageLookupByLibrary.simpleMessage("tệp mới"),
    "aiCutLines": m3,
    "aiCutText": MessageLookupByLibrary.simpleMessage(
      "Phần còn lại của tin này xem trên máy tính.",
    ),
    "aiEmpty": MessageLookupByLibrary.simpleMessage(
      "Chưa có tin nhắn. Viết tin đầu tiên ở ô dưới.",
    ),
    "aiForceStop": MessageLookupByLibrary.simpleMessage("Dừng hẳn"),
    "aiFromComputerOnly": MessageLookupByLibrary.simpleMessage(
      "Quá lớn để xem trên điện thoại. Xem trên máy tính.",
    ),
    "aiFromPhone": MessageLookupByLibrary.simpleMessage("từ điện thoại"),
    "aiGroup": MessageLookupByLibrary.simpleMessage("Phiên AI"),
    "aiItemOnComputer": MessageLookupByLibrary.simpleMessage(
      "Điện thoại chưa hỗ trợ loại mục này. Xem trên máy tính.",
    ),
    "aiJumpLatest": MessageLookupByLibrary.simpleMessage("Mới nhất"),
    "aiLoadEarlier": MessageLookupByLibrary.simpleMessage("Tải thêm"),
    "aiModeAcceptEdits": MessageLookupByLibrary.simpleMessage("Tự sửa tệp"),
    "aiModeAuto": MessageLookupByLibrary.simpleMessage("Tự động"),
    "aiModeBypass": MessageLookupByLibrary.simpleMessage("Bỏ qua mọi quyền"),
    "aiModeDefault": MessageLookupByLibrary.simpleMessage("Hỏi trước"),
    "aiModePlan": MessageLookupByLibrary.simpleMessage("Lập kế hoạch"),
    "aiMoreDiffs": m4,
    "aiNewAgent": MessageLookupByLibrary.simpleMessage("Agent"),
    "aiNewFolder": MessageLookupByLibrary.simpleMessage("Thư mục"),
    "aiNewNoAgents": MessageLookupByLibrary.simpleMessage(
      "Chưa có agent nào sẵn sàng trên máy tính. Hãy thiết lập trong Cài đặt › Agent.",
    ),
    "aiNewNoFolders": MessageLookupByLibrary.simpleMessage(
      "Hãy đặt thư mục cho một dự án trên máy tính trước (Cài đặt › Dự án).",
    ),
    "aiNewSession": MessageLookupByLibrary.simpleMessage("Phiên AI mới"),
    "aiNewStart": MessageLookupByLibrary.simpleMessage("Bắt đầu"),
    "aiNoOutput": MessageLookupByLibrary.simpleMessage("Không có đầu ra"),
    "aiNoticeCannotResume": MessageLookupByLibrary.simpleMessage(
      "Agent này không khôi phục được phiên cũ; đã mở phiên mới.",
    ),
    "aiNoticeExited": m5,
    "aiNoticeFolderMissing": MessageLookupByLibrary.simpleMessage(
      "Thư mục của phiên không còn. Chọn thư mục trên máy tính.",
    ),
    "aiNoticeInvalid": m6,
    "aiNoticeLogin": m7,
    "aiNoticeMissing": m8,
    "aiNoticeNode": m9,
    "aiNoticeNotInstalled": m10,
    "aiNoticeOther": MessageLookupByLibrary.simpleMessage(
      "Thông báo từ máy tính.",
    ),
    "aiNoticeStartFailed": m11,
    "aiNoticeUndoOff": MessageLookupByLibrary.simpleMessage(
      "Hoàn tác đang tắt cho dự án này.",
    ),
    "aiNoticeUndoOffReason": m12,
    "aiNoticeUndoOffTurn": m13,
    "aiOpenOutcomeUnknown": MessageLookupByLibrary.simpleMessage(
      "Có thể phiên mới chưa được tạo. Hãy xem lại danh sách trước khi thử lại.",
    ),
    "aiOutcomeUnknown": MessageLookupByLibrary.simpleMessage(
      "Có thể chưa gửi được — kết nối bị gián đoạn. Hãy xem lại phiên trước khi thử lại.",
    ),
    "aiPermAllowAlways": MessageLookupByLibrary.simpleMessage("Luôn cho phép"),
    "aiPermAllowOnce": MessageLookupByLibrary.simpleMessage("Cho phép"),
    "aiPermDetails": MessageLookupByLibrary.simpleMessage("Xem chi tiết"),
    "aiPermMore": m14,
    "aiPermOnComputer": MessageLookupByLibrary.simpleMessage(
      "Trả lời yêu cầu này trên máy tính.",
    ),
    "aiPermOption": MessageLookupByLibrary.simpleMessage("Lựa chọn"),
    "aiPermRejectAlways": MessageLookupByLibrary.simpleMessage("Luôn từ chối"),
    "aiPermRejectOnce": MessageLookupByLibrary.simpleMessage("Từ chối"),
    "aiPermTitle": m15,
    "aiPlan": m16,
    "aiQueue": MessageLookupByLibrary.simpleMessage("Xếp hàng"),
    "aiQueueFull": MessageLookupByLibrary.simpleMessage(
      "Đã có 5 tin đang chờ.",
    ),
    "aiQueued": MessageLookupByLibrary.simpleMessage("Đang xếp hàng"),
    "aiReconnecting": MessageLookupByLibrary.simpleMessage(
      "Đang kết nối lại… nội dung có thể chưa mới nhất.",
    ),
    "aiRefused": MessageLookupByLibrary.simpleMessage(
      "Máy tính không nhận yêu cầu này.",
    ),
    "aiRemoveQueued": MessageLookupByLibrary.simpleMessage("Bỏ khỏi hàng đợi"),
    "aiRequestFailed": m17,
    "aiRowSubtitle": m18,
    "aiSend": MessageLookupByLibrary.simpleMessage("Gửi"),
    "aiStateAgentOff": MessageLookupByLibrary.simpleMessage(
      "Agent đang tắt trên máy tính",
    ),
    "aiStateClosed": MessageLookupByLibrary.simpleMessage("Đã đóng"),
    "aiStateFailed": MessageLookupByLibrary.simpleMessage("Lỗi"),
    "aiStateIdle": MessageLookupByLibrary.simpleMessage("Đang chờ"),
    "aiStateNeedsAuth": MessageLookupByLibrary.simpleMessage(
      "Cần đăng nhập trên máy tính",
    ),
    "aiStateNeedsInput": MessageLookupByLibrary.simpleMessage(
      "Cần bạn trả lời",
    ),
    "aiStateNoFolder": MessageLookupByLibrary.simpleMessage(
      "Chọn thư mục trên máy tính",
    ),
    "aiStateRunning": MessageLookupByLibrary.simpleMessage("Đang chạy"),
    "aiStateStarting": MessageLookupByLibrary.simpleMessage("Đang khởi động"),
    "aiStateStopped": MessageLookupByLibrary.simpleMessage("Chưa chạy"),
    "aiStop": MessageLookupByLibrary.simpleMessage("Dừng"),
    "aiStopping": MessageLookupByLibrary.simpleMessage("Đang dừng…"),
    "aiThought": MessageLookupByLibrary.simpleMessage("Suy nghĩ"),
    "aiTooLong": m19,
    "aiToolAwaiting": MessageLookupByLibrary.simpleMessage("chờ bạn"),
    "aiToolCreate": m20,
    "aiToolDelete": m21,
    "aiToolDone": MessageLookupByLibrary.simpleMessage("xong"),
    "aiToolEdit": m22,
    "aiToolExecute": m23,
    "aiToolFailed": MessageLookupByLibrary.simpleMessage("lỗi"),
    "aiToolFetch": m24,
    "aiToolMove": m25,
    "aiToolPending": MessageLookupByLibrary.simpleMessage("chờ"),
    "aiToolRead": m26,
    "aiToolRejected": MessageLookupByLibrary.simpleMessage("bị từ chối"),
    "aiToolRunningFor": m27,
    "aiToolSearch": m28,
    "aiToolStopped": MessageLookupByLibrary.simpleMessage("đã dừng"),
    "aiToolSwitchMode": MessageLookupByLibrary.simpleMessage("Đổi chế độ"),
    "aiTurnFailed": m29,
    "aiTurnFiles": m30,
    "aiTurnInterrupted": m31,
    "aiTurnStopped": m32,
    "aiTurnSummary": m33,
    "aiUnavailable": MessageLookupByLibrary.simpleMessage(
      "Mở ShellX trên máy tính để dùng phiên AI.",
    ),
    "aiUndoBroadFolder": MessageLookupByLibrary.simpleMessage(
      "thư mục này là thư mục home hoặc gốc ổ đĩa",
    ),
    "aiUndoFailed": MessageLookupByLibrary.simpleMessage(
      "chụp điểm khôi phục lỗi",
    ),
    "aiUndoGitTooOld": MessageLookupByLibrary.simpleMessage("git cũ hơn 2.26"),
    "aiUndoNoCommandLineTools": MessageLookupByLibrary.simpleMessage(
      "chưa cài Command Line Tools",
    ),
    "aiUndoNoGit": MessageLookupByLibrary.simpleMessage("không tìm thấy git"),
    "aiUndoTooManyFiles": MessageLookupByLibrary.simpleMessage(
      "hơn 200 000 tệp",
    ),
    "aiUndoTooSlow": MessageLookupByLibrary.simpleMessage(
      "lần chụp đầu quá 30 s",
    ),
    "aiUntitled": MessageLookupByLibrary.simpleMessage("Phiên AI mới"),
    "aiUpdateDesktop": MessageLookupByLibrary.simpleMessage(
      "Cập nhật ShellX trên máy tính để dùng phiên AI từ điện thoại.",
    ),
    "aiYouChose": m34,
    "appTitle": MessageLookupByLibrary.simpleMessage("ShellX"),
    "arrowPadDown": MessageLookupByLibrary.simpleMessage("Xuống"),
    "arrowPadLabel": MessageLookupByLibrary.simpleMessage(
      "Bàn xoay mũi tên. Kéo để di chuyển con trỏ.",
    ),
    "arrowPadLeft": MessageLookupByLibrary.simpleMessage("Trái"),
    "arrowPadRight": MessageLookupByLibrary.simpleMessage("Phải"),
    "arrowPadUp": MessageLookupByLibrary.simpleMessage("Lên"),
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
    "deleteAccountLoseAccount": m35,
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
    "desktopClosedByHost": MessageLookupByLibrary.simpleMessage(
      "Máy tính đã ngắt điện thoại khỏi terminal này.",
    ),
    "desktopDriverBanner": MessageLookupByLibrary.simpleMessage(
      "Máy tính đang dùng terminal này",
    ),
    "desktopDriverTakeOver": MessageLookupByLibrary.simpleMessage(
      "Chạm để dùng tiếp",
    ),
    "desktopStillRunning": MessageLookupByLibrary.simpleMessage(
      "Terminal vẫn chạy trên máy tính.",
    ),
    "desktopTerminalGone": MessageLookupByLibrary.simpleMessage(
      "Mất kết nối với terminal này trên máy tính.",
    ),
    "desktopTerminalLabel": MessageLookupByLibrary.simpleMessage(
      "Terminal trên máy tính",
    ),
    "desktopWindowClosed": MessageLookupByLibrary.simpleMessage(
      "Cửa sổ terminal trên máy tính đã đóng.",
    ),
    "emailHint": MessageLookupByLibrary.simpleMessage("email@example.com"),
    "emailLabel": MessageLookupByLibrary.simpleMessage("Email"),
    "emptyStep1": m36,
    "emptyStep2": MessageLookupByLibrary.simpleMessage(
      "Đăng nhập cùng tài khoản này.",
    ),
    "emptyStep3": m37,
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
    "errorSpawnFailed": m38,
    "errorTimeout": MessageLookupByLibrary.simpleMessage(
      "Máy tính không phản hồi. Hãy thử lại.",
    ),
    "errorUnknown": m39,
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
    "lastSeenDate": m40,
    "lastSeenJustNow": MessageLookupByLibrary.simpleMessage("vừa xong"),
    "lastSeenMinutes": m41,
    "lastSeenToday": m42,
    "lastSeenUnknown": MessageLookupByLibrary.simpleMessage("không rõ"),
    "lastSeenYesterday": m43,
    "linkSheetCopy": MessageLookupByLibrary.simpleMessage("Sao chép liên kết"),
    "linkSheetOpen": MessageLookupByLibrary.simpleMessage("Mở"),
    "linkSheetTitle": MessageLookupByLibrary.simpleMessage("Mở liên kết?"),
    "loadMoreFailPleaseTryAgain": MessageLookupByLibrary.simpleMessage(
      "Tải thêm thất bại\nHãy thử lại",
    ),
    "lockReason": MessageLookupByLibrary.simpleMessage("Mở khóa ShellX"),
    "lockSubtitle": MessageLookupByLibrary.simpleMessage(
      "Mở khóa để xem các máy và phiên terminal của bạn.",
    ),
    "lockTitle": MessageLookupByLibrary.simpleMessage("ShellX đang khóa"),
    "lockUnlockWith": m44,
    "loginButton": MessageLookupByLibrary.simpleMessage("Đăng nhập"),
    "loginSubtitle": MessageLookupByLibrary.simpleMessage(
      "Dùng cùng tài khoản với ShellX trên máy tính.",
    ),
    "loginTitle": MessageLookupByLibrary.simpleMessage("Đăng nhập"),
    "machineLastOnline": m45,
    "machineLastUsed": MessageLookupByLibrary.simpleMessage("Dùng gần nhất"),
    "machineNewOutput": MessageLookupByLibrary.simpleMessage("Có chữ mới"),
    "machineNotPaired": MessageLookupByLibrary.simpleMessage("Chưa ghép nối"),
    "machineOffline": MessageLookupByLibrary.simpleMessage("Máy đang offline."),
    "machineOnline": MessageLookupByLibrary.simpleMessage("Online"),
    "machineTabs": m46,
    "machineTabsActivity": m47,
    "machineWaiting": MessageLookupByLibrary.simpleMessage("Đang chờ kết nối"),
    "machinesCheckConnection": MessageLookupByLibrary.simpleMessage(
      "Hãy kiểm tra kết nối mạng.",
    ),
    "machinesErrorTitle": MessageLookupByLibrary.simpleMessage(
      "Không tải được danh sách máy",
    ),
    "machinesOfflineHeader": MessageLookupByLibrary.simpleMessage("Offline"),
    "machinesReload": MessageLookupByLibrary.simpleMessage("Tải lại"),
    "machinesRetry": MessageLookupByLibrary.simpleMessage("Thử lại"),
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
    "pairingSucceededBody": m48,
    "passwordHide": MessageLookupByLibrary.simpleMessage("Ẩn mật khẩu"),
    "passwordHint": MessageLookupByLibrary.simpleMessage("Mật khẩu"),
    "passwordLabel": MessageLookupByLibrary.simpleMessage("Mật khẩu"),
    "passwordMissing": m49,
    "passwordRule": MessageLookupByLibrary.simpleMessage("Từ 8 đến 128 ký tự."),
    "passwordShow": MessageLookupByLibrary.simpleMessage("Hiện mật khẩu"),
    "passwordTooLong": m50,
    "pickerAgentDone": m51,
    "pickerAgentIdle": m52,
    "pickerAgentNeedsInput": m53,
    "pickerAgentRunning": m54,
    "pickerAttachedElsewhere": MessageLookupByLibrary.simpleMessage(
      "đang mở trên thiết bị khác",
    ),
    "pickerDesktopGroup": MessageLookupByLibrary.simpleMessage(
      "Terminal trên máy tính",
    ),
    "pickerHintOpenNewWindow": MessageLookupByLibrary.simpleMessage(
      "Chỉ các cửa sổ terminal mở sau khi bật chia sẻ mới hiện ở đây. Mở một cửa sổ terminal mới trên máy tính.",
    ),
    "pickerHintSharingOff": MessageLookupByLibrary.simpleMessage(
      "Bật \'Chia sẻ terminal với điện thoại\' trong menu ShellX trên máy tính để xem các terminal đang mở ở đây.",
    ),
    "pickerHintUpdateDesktop": MessageLookupByLibrary.simpleMessage(
      "Cập nhật ShellX trên máy tính để xem các terminal đang mở.",
    ),
    "pickerNewSession": MessageLookupByLibrary.simpleMessage("Phiên mới"),
    "pickerOpen": MessageLookupByLibrary.simpleMessage("Mở"),
    "pickerShellxGroup": MessageLookupByLibrary.simpleMessage("Phiên ShellX"),
    "pickerStarted": m55,
    "pickerSubtitle": MessageLookupByLibrary.simpleMessage(
      "Mở lại phiên cũ để xem tiếp đúng chỗ đã dừng, hoặc tạo phiên mới.",
    ),
    "pickerTitle": m56,
    "privacyLink": MessageLookupByLibrary.simpleMessage(
      "Chính sách quyền riêng tư",
    ),
    "registerButton": MessageLookupByLibrary.simpleMessage("Tạo tài khoản"),
    "registerSubtitle": MessageLookupByLibrary.simpleMessage(
      "Một tài khoản cho điện thoại và mọi máy tính của bạn.",
    ),
    "registerTitle": MessageLookupByLibrary.simpleMessage("Tạo tài khoản"),
    "replyBarLabel": MessageLookupByLibrary.simpleMessage(
      "Trả lời nhanh cho agent",
    ),
    "replyKeyEnter": MessageLookupByLibrary.simpleMessage("Enter"),
    "replyKeyEscape": MessageLookupByLibrary.simpleMessage("Thoát"),
    "replyKeyNo": MessageLookupByLibrary.simpleMessage("Không"),
    "replyKeyOption": m57,
    "replyKeyYes": MessageLookupByLibrary.simpleMessage("Có"),
    "replyShowExtraKeys": MessageLookupByLibrary.simpleMessage("Hiện phím phụ"),
    "retry": MessageLookupByLibrary.simpleMessage("Thử lại"),
    "scanAgain": MessageLookupByLibrary.simpleMessage("Quét lại"),
    "scanQrButton": MessageLookupByLibrary.simpleMessage("Quét mã QR"),
    "scannerCameraDenied": MessageLookupByLibrary.simpleMessage(
      "Cần quyền camera để quét mã QR. Hãy cho phép trong Cài đặt của điện thoại.",
    ),
    "scannerCameraError": MessageLookupByLibrary.simpleMessage(
      "Không mở được camera.",
    ),
    "scannerCardBody": m58,
    "scannerCardTitle": MessageLookupByLibrary.simpleMessage(
      "Mã nằm trên máy tính của bạn",
    ),
    "scannerPairing": MessageLookupByLibrary.simpleMessage("Đang ghép nối…"),
    "scannerTitle": MessageLookupByLibrary.simpleMessage("Quét mã ghép nối"),
    "sessionEnded": MessageLookupByLibrary.simpleMessage("Phiên đã kết thúc"),
    "sessionExitedBody": m59,
    "sessionGoneBody": MessageLookupByLibrary.simpleMessage(
      "Máy tính không còn phiên này. Nội dung ở trên vẫn đọc và copy được.",
    ),
    "sessionsLoading": MessageLookupByLibrary.simpleMessage(
      "Đang lấy danh sách phiên…",
    ),
    "settingsAccountGroup": MessageLookupByLibrary.simpleMessage("Tài khoản"),
    "settingsAppGroup": MessageLookupByLibrary.simpleMessage("Ứng dụng"),
    "settingsBiometricUnavailable": MessageLookupByLibrary.simpleMessage(
      "Thiết bị chưa đặt mã khóa hoặc sinh trắc học",
    ),
    "settingsDeleteAccount": MessageLookupByLibrary.simpleMessage(
      "Xóa tài khoản",
    ),
    "settingsEmail": MessageLookupByLibrary.simpleMessage("Email"),
    "settingsFixedHeight": MessageLookupByLibrary.simpleMessage(
      "Giữ cỡ terminal khi mở bàn phím",
    ),
    "settingsFixedHeightHint": MessageLookupByLibrary.simpleMessage(
      "Bàn phím che lên terminal thay vì làm nó co lại.",
    ),
    "settingsFontSize": MessageLookupByLibrary.simpleMessage("Cỡ chữ mặc định"),
    "settingsLicenses": MessageLookupByLibrary.simpleMessage(
      "Giấy phép mã nguồn mở",
    ),
    "settingsLockFootnote": MessageLookupByLibrary.simpleMessage(
      "Hỏi khi mở app và khi quay lại sau hơn 5 phút.",
    ),
    "settingsLockWith": m60,
    "settingsLogout": MessageLookupByLibrary.simpleMessage("Đăng xuất"),
    "settingsLogoutConfirm": MessageLookupByLibrary.simpleMessage(
      "Đăng xuất khỏi ShellX? Các máy đã ghép nối vẫn được giữ cho lần đăng nhập sau.",
    ),
    "settingsNoPairedMachines": MessageLookupByLibrary.simpleMessage(
      "Chưa ghép nối máy nào.",
    ),
    "settingsNotifications": MessageLookupByLibrary.simpleMessage(
      "Thông báo đẩy",
    ),
    "settingsNotificationsFootnote": MessageLookupByLibrary.simpleMessage(
      "Báo khi một lệnh chạy lâu trên máy tính xong hoặc khi chương trình gửi thông báo. Chọn ngưỡng thời gian trong menu ShellX trên máy tính.",
    ),
    "settingsNotificationsGroup": MessageLookupByLibrary.simpleMessage(
      "Thông báo",
    ),
    "settingsNotificationsOff": MessageLookupByLibrary.simpleMessage(
      "Đang tắt",
    ),
    "settingsNotificationsOffFootnote": MessageLookupByLibrary.simpleMessage(
      "Thông báo đang tắt — mở Cài đặt hệ thống để bật.",
    ),
    "settingsNotificationsOn": MessageLookupByLibrary.simpleMessage("Đang bật"),
    "settingsNotificationsOpenSystem": MessageLookupByLibrary.simpleMessage(
      "Mở Cài đặt hệ thống",
    ),
    "settingsNotificationsTurnOn": MessageLookupByLibrary.simpleMessage(
      "Bật thông báo",
    ),
    "settingsPairedMachines": MessageLookupByLibrary.simpleMessage(
      "Máy đã ghép nối",
    ),
    "settingsPrivacy": MessageLookupByLibrary.simpleMessage(
      "Chính sách quyền riêng tư",
    ),
    "settingsSecurityGroup": MessageLookupByLibrary.simpleMessage("Bảo mật"),
    "settingsTerminalGroup": MessageLookupByLibrary.simpleMessage("Terminal"),
    "settingsTerms": MessageLookupByLibrary.simpleMessage("Điều khoản sử dụng"),
    "settingsTheme": MessageLookupByLibrary.simpleMessage("Giao diện"),
    "settingsThemeDark": MessageLookupByLibrary.simpleMessage("Tối"),
    "settingsThemeLight": MessageLookupByLibrary.simpleMessage("Sáng"),
    "settingsThemeSystem": MessageLookupByLibrary.simpleMessage("Theo máy"),
    "settingsTitle": MessageLookupByLibrary.simpleMessage("Cài đặt"),
    "settingsTooltip": MessageLookupByLibrary.simpleMessage("Cài đặt"),
    "settingsUnpair": MessageLookupByLibrary.simpleMessage("Bỏ ghép nối"),
    "settingsUnpairConfirm": m61,
    "settingsUnpairFailed": MessageLookupByLibrary.simpleMessage(
      "Chưa bỏ ghép nối được.",
    ),
    "settingsVersion": m62,
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
    "termsNotice": m63,
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
      "Hãy nhập địa chỉ email hợp lệ.",
    ),
    "validationEmailRequired": MessageLookupByLibrary.simpleMessage(
      "Cần nhập email.",
    ),
    "validationPasswordConfirmRequired": MessageLookupByLibrary.simpleMessage(
      "Hãy xác nhận mật khẩu.",
    ),
    "validationPasswordDigit": MessageLookupByLibrary.simpleMessage(
      "Mật khẩu phải có ít nhất một chữ số.",
    ),
    "validationPasswordLowercase": MessageLookupByLibrary.simpleMessage(
      "Mật khẩu phải có ít nhất một chữ thường.",
    ),
    "validationPasswordMinLength": m64,
    "validationPasswordNotMatch": MessageLookupByLibrary.simpleMessage(
      "Mật khẩu không khớp.",
    ),
    "validationPasswordRequired": MessageLookupByLibrary.simpleMessage(
      "Cần nhập mật khẩu.",
    ),
    "validationPasswordSpecialChar": MessageLookupByLibrary.simpleMessage(
      "Mật khẩu phải có ít nhất một ký tự đặc biệt.",
    ),
    "validationPasswordUppercase": MessageLookupByLibrary.simpleMessage(
      "Mật khẩu phải có ít nhất một chữ hoa.",
    ),
    "validationPhoneInvalid": MessageLookupByLibrary.simpleMessage(
      "Hãy nhập số điện thoại hợp lệ.",
    ),
    "validationPhoneRequired": MessageLookupByLibrary.simpleMessage(
      "Cần nhập số điện thoại.",
    ),
    "validationTextMaxLength": m65,
    "validationTextMinLength": m66,
    "validationTextRequired": MessageLookupByLibrary.simpleMessage(
      "Trường này là bắt buộc.",
    ),
    "viewAsTextCopyAll": MessageLookupByLibrary.simpleMessage(
      "Sao chép tất cả",
    ),
    "viewAsTextEmpty": MessageLookupByLibrary.simpleMessage("Chưa có nội dung"),
    "viewAsTextRefresh": MessageLookupByLibrary.simpleMessage("Làm mới"),
    "viewAsTextTitle": MessageLookupByLibrary.simpleMessage("Văn bản terminal"),
    "viewAsTextTooltip": MessageLookupByLibrary.simpleMessage(
      "Xem dạng văn bản",
    ),
    "viewAsTextTruncated": m67,
    "voiceClose": MessageLookupByLibrary.simpleMessage("Đóng"),
    "voiceDetached": MessageLookupByLibrary.simpleMessage(
      "Phiên đã ngắt khỏi điện thoại — gắn lại để gửi",
    ),
    "voiceDraftSaved": MessageLookupByLibrary.simpleMessage("Có bản nháp"),
    "voiceEnded": MessageLookupByLibrary.simpleMessage(
      "Phiên đã kết thúc — mở phiên mới để gửi",
    ),
    "voiceFailed": MessageLookupByLibrary.simpleMessage(
      "Không nhận dạng được, hãy thử lại",
    ),
    "voiceHintEn": MessageLookupByLibrary.simpleMessage(
      "Nói hoặc gõ… nói “send” để gửi",
    ),
    "voiceHintVi": MessageLookupByLibrary.simpleMessage(
      "Nói hoặc gõ… nói “gửi” để gửi",
    ),
    "voiceLanguageEn": MessageLookupByLibrary.simpleMessage("Tiếng Anh"),
    "voiceLanguageVi": MessageLookupByLibrary.simpleMessage("Tiếng Việt"),
    "voiceListeningAnnounce": MessageLookupByLibrary.simpleMessage("Đang nghe"),
    "voiceListeningEn": MessageLookupByLibrary.simpleMessage(
      "Đang nghe… nói “send” để gửi",
    ),
    "voiceListeningVi": MessageLookupByLibrary.simpleMessage(
      "Đang nghe… nói “gửi” để gửi",
    ),
    "voiceLocaleUnavailableEn": MessageLookupByLibrary.simpleMessage(
      "Máy chưa hỗ trợ nhận dạng tiếng Anh — thử VI",
    ),
    "voiceLocaleUnavailableVi": MessageLookupByLibrary.simpleMessage(
      "Máy chưa hỗ trợ nhận dạng tiếng Việt — thử EN",
    ),
    "voiceMicTooltip": MessageLookupByLibrary.simpleMessage("Nói lệnh"),
    "voiceNetwork": MessageLookupByLibrary.simpleMessage(
      "Cần kết nối mạng để nhận dạng giọng nói",
    ),
    "voiceNoPermission": MessageLookupByLibrary.simpleMessage(
      "Cần quyền micro và nhận dạng giọng nói để nói lệnh",
    ),
    "voiceNotLive": MessageLookupByLibrary.simpleMessage(
      "Phiên chưa kết nối — gửi được khi kết nối lại",
    ),
    "voiceSend": MessageLookupByLibrary.simpleMessage("Gửi"),
    "voiceSendEnter": MessageLookupByLibrary.simpleMessage("Gửi phím Enter"),
    "voiceStopTooltip": MessageLookupByLibrary.simpleMessage("Dừng nghe"),
    "voiceTarget": m68,
    "voiceUnsupported": MessageLookupByLibrary.simpleMessage(
      "Máy này không hỗ trợ nhận dạng giọng nói",
    ),
  };
}
