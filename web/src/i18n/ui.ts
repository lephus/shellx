export type Lang = 'vi' | 'en';
export type Page = 'home' | 'privacy' | 'terms';

const paths: Record<Lang, Record<Page, string>> = {
  vi: { home: '/', privacy: '/privacy/', terms: '/terms/' },
  en: { home: '/en/', privacy: '/en/privacy/', terms: '/en/terms/' },
};

export function pathFor(lang: Lang, page: Page): string {
  return paths[lang][page];
}

export function otherLang(lang: Lang): Lang {
  return lang === 'vi' ? 'en' : 'vi';
}

const vi = {
  languageName: 'Tiếng Việt',
  homeTitle: 'ShellX — Terminal máy tính ngay trên điện thoại',
  homeDescription:
    'Điều khiển terminal trên máy Mac hoặc PC từ điện thoại, ở bất kỳ đâu có Internet, qua kết nối mã hóa đầu cuối.',
  tagline: 'Terminal máy tính của bạn, ngay trên điện thoại.',
  intro:
    'Cài agent ShellX trên máy Mac hoặc PC, rồi mở và điều khiển các phiên terminal từ điện thoại ở bất kỳ đâu có Internet. Không cần mở port trên router, không cần mang laptop theo.',
  e2e: 'Kết nối được mã hóa đầu cuối: máy chủ trung gian không đọc được nội dung terminal của bạn.',
  heroStatus: 'đã ghép nối · mã hóa đầu cuối',
  featuresHeading: 'Tính năng',
  feature1: 'Mở và điều khiển terminal của máy Mac hoặc PC từ điện thoại, ở bất kỳ đâu có Internet.',
  feature2: 'Mã hóa đầu cuối bằng giao thức Noise — máy chủ chuyển tiếp không đọc được nội dung.',
  feature3: 'Không cần mở port trên router, không cần IP tĩnh hay VPN.',
  feature4: 'Nhiều phiên terminal cùng lúc, chuyển qua lại như đang ngồi trước máy.',
  feature5: 'Ghép nối điện thoại với máy tính bằng mã QR; khóa bí mật không bao giờ rời thiết bị.',
  feature6: 'Agent cho macOS và Windows; app cho iOS và Android.',
  stepsHeading: 'Bắt đầu trong ba bước',
  step1: 'Cài agent trên máy tính và đăng ký tài khoản.',
  step2: 'Cài app trên điện thoại và đăng nhập cùng tài khoản.',
  step3: 'Chọn "Ghép nối điện thoại…" ở menu khay trên máy tính và quét mã QR bằng điện thoại.',
  securityHeading: 'Bảo mật',
  security1: 'Nội dung terminal được mã hóa đầu cuối: chỉ điện thoại và máy tính của bạn giải mã được.',
  security2: 'Máy chủ chuyển tiếp chỉ thấy gói dữ liệu đã mã hóa — không bao giờ thấy lệnh hay kết quả.',
  security3: 'Mật khẩu được băm bằng argon2id; mã truy cập chỉ lưu ở dạng băm SHA-256.',
  security4: 'Không log nội dung terminal, không analytics, không cookie.',
  securityMore: 'Chi tiết trong Chính sách quyền riêng tư',
  faqHeading: 'Câu hỏi thường gặp',
  faqQ1: 'Tôi có cần mở port trên router hay IP tĩnh không?',
  faqA1: 'Không. Agent trên máy tính và app trên điện thoại đều tự kết nối ra máy chủ chuyển tiếp, nên không cần mở port, không cần IP tĩnh hay VPN.',
  faqQ2: 'Điện thoại mất mạng giữa chừng thì sao?',
  faqA2: 'Agent giữ tối đa 256 KiB output gần nhất của mỗi phiên trong bộ nhớ máy tính; khi điện thoại kết nối lại, phần output phát sinh trong lúc mất mạng được phát lại.',
  faqQ3: 'ShellX lưu những dữ liệu gì trên máy chủ?',
  faqA3: 'Chỉ email, mật khẩu đã băm, thông tin thiết bị và bản ghi ghép nối. Nội dung terminal được mã hóa đầu cuối nên máy chủ không đọc được và không lưu.',
  faqQ4: 'ShellX có mất phí không?',
  faqA4: 'ShellX hiện miễn phí.',
  faqQ5: 'ShellX chạy trên nền tảng nào?',
  faqA5: 'Agent: macOS 12 trở lên, Windows 10 (bản 1809) trở lên. App: iOS 15 trở lên, Android 8.0 trở lên.',
  desktopHeading: 'Agent cho máy tính',
  mobileHeading: 'App cho điện thoại',
  version: 'Phiên bản',
  macos: 'Tải cho macOS',
  macosRequirement: 'macOS 12 trở lên · tệp .dmg',
  windows: 'Tải cho Windows',
  windowsRequirement: 'Windows 10 (bản 1809) trở lên · tệp .exe',
  appStore: 'App Store',
  appStoreRequirement: 'iOS 15 trở lên',
  googlePlay: 'Google Play',
  googlePlayRequirement: 'Android 8.0 trở lên',
  comingSoon: 'Sắp ra mắt',
  privacy: 'Chính sách quyền riêng tư',
  terms: 'Điều khoản sử dụng',
  download: 'Tải về',
  contact: 'Hỗ trợ',
  lastUpdated: 'Cập nhật lần cuối',
  notFoundTitle: 'Không tìm thấy trang',
  notFoundBody: 'Trang bạn tìm không tồn tại hoặc đã được chuyển đi.',
  backHome: 'Về trang chủ',
};

type Strings = typeof vi;

const en: Strings = {
  languageName: 'English',
  homeTitle: `ShellX — Your computer's terminal on your phone`,
  homeDescription:
    'Control the terminal on your Mac or PC from your phone, from anywhere with an Internet connection, over an end-to-end encrypted connection.',
  tagline: `Your computer's terminal, right on your phone.`,
  intro:
    'Install the ShellX agent on your Mac or PC, then open and control terminal sessions from your phone wherever you have an Internet connection. No router ports to open, no laptop to carry.',
  e2e: 'End-to-end encrypted: the relay server in the middle cannot read your terminal content.',
  heroStatus: 'paired · end-to-end encrypted',
  featuresHeading: 'Features',
  feature1: 'Open and control your Mac or PC terminal from your phone, anywhere with an Internet connection.',
  feature2: 'End-to-end encrypted with the Noise protocol — the relay cannot read the content.',
  feature3: 'No router ports to open, no static IP, no VPN.',
  feature4: 'Multiple terminal sessions at once, switch as if you were at the machine.',
  feature5: `Pair phone and computer with a QR code; private keys never leave the device.`,
  feature6: 'Agent for macOS and Windows; app for iOS and Android.',
  stepsHeading: 'Get started in three steps',
  step1: 'Install the agent on your computer and create an account.',
  step2: 'Install the phone app and sign in with the same account.',
  step3: 'Open the tray menu on your computer, choose to pair a phone, and scan the QR code with your phone.',
  securityHeading: 'Security',
  security1: `Terminal content is end-to-end encrypted: only your phone and your computer can decrypt it.`,
  security2: 'The relay only ever sees encrypted frames — never commands or output.',
  security3: 'Passwords are hashed with argon2id; access tokens are stored only as SHA-256 hashes.',
  security4: 'No terminal-content logs, no analytics, no cookies.',
  securityMore: 'Details in the Privacy Policy',
  faqHeading: 'FAQ',
  faqQ1: 'Do I need to open router ports or have a static IP?',
  faqA1: 'No. Both the desktop agent and the phone app dial out to the relay, so there are no ports to open, no static IP, no VPN.',
  faqQ2: `What if my phone loses its connection?`,
  faqA2: `The agent keeps up to 256 KiB of each session's most recent output in your computer's memory; when the phone reconnects, the output produced while it was away is replayed.`,
  faqQ3: 'What does ShellX store on its servers?',
  faqA3: `Only your email, a password hash, device information and pairing records. Terminal content is end-to-end encrypted, so the server cannot read or store it.`,
  faqQ4: 'Does ShellX cost anything?',
  faqA4: 'ShellX is currently free.',
  faqQ5: 'Which platforms does ShellX run on?',
  faqA5: 'Agent: macOS 12 or later, Windows 10 (1809) or later. App: iOS 15 or later, Android 8.0 or later.',
  desktopHeading: 'Agent for your computer',
  mobileHeading: 'App for your phone',
  version: 'Version',
  macos: 'Download for macOS',
  macosRequirement: 'macOS 12 or later · .dmg file',
  windows: 'Download for Windows',
  windowsRequirement: 'Windows 10 (version 1809) or later · .exe file',
  appStore: 'App Store',
  appStoreRequirement: 'iOS 15 or later',
  googlePlay: 'Google Play',
  googlePlayRequirement: 'Android 8.0 or later',
  comingSoon: 'Coming soon',
  privacy: 'Privacy Policy',
  terms: 'Terms of Use',
  download: 'Download',
  contact: 'Support',
  lastUpdated: 'Last updated',
  notFoundTitle: 'Page not found',
  notFoundBody: 'The page you are looking for does not exist or has moved.',
  backHome: 'Back to home',
};

export const ui: Record<Lang, Strings> = { vi, en };
