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
  stepsHeading: 'Bắt đầu trong ba bước',
  step1: 'Cài agent trên máy tính và đăng ký tài khoản.',
  step2: 'Cài app trên điện thoại và đăng nhập cùng tài khoản.',
  step3: 'Chọn "Ghép nối điện thoại…" ở menu khay trên máy tính và quét mã QR bằng điện thoại.',
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
  contact: 'Hỗ trợ',
  lastUpdated: 'Cập nhật lần cuối',
  notFoundTitle: 'Không tìm thấy trang',
  notFoundBody: 'Trang bạn tìm không tồn tại hoặc đã được chuyển đi.',
  backHome: 'Về trang chủ',
};

type Strings = typeof vi;

const en: Strings = {
  languageName: 'English',
  homeTitle: "ShellX — Your computer's terminal on your phone",
  homeDescription:
    'Control the terminal on your Mac or PC from your phone, from anywhere with an Internet connection, over an end-to-end encrypted connection.',
  tagline: "Your computer's terminal, right on your phone.",
  intro:
    'Install the ShellX agent on your Mac or PC, then open and control terminal sessions from your phone wherever you have an Internet connection. No router ports to open, no laptop to carry.',
  e2e: 'End-to-end encrypted: the relay server in the middle cannot read your terminal content.',
  stepsHeading: 'Get started in three steps',
  step1: 'Install the agent on your computer and create an account.',
  step2: 'Install the phone app and sign in with the same account.',
  step3: 'Open the tray menu on your computer, choose to pair a phone, and scan the QR code with your phone.',
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
  contact: 'Support',
  lastUpdated: 'Last updated',
  notFoundTitle: 'Page not found',
  notFoundBody: 'The page you are looking for does not exist or has moved.',
  backHome: 'Back to home',
};

export const ui: Record<Lang, Strings> = { vi, en };
