import config from '../site.config.json';

// The single source of truth for download and store links is src/site.config.json.
// Installer file names must match what release/ uploads to R2:
//   desktop/<version>/ShellX-<version>.dmg
//   desktop/<version>/ShellX-Setup-<version>.exe
export const desktopVersion: string = config.desktopVersion;
export const supportEmail: string = config.supportEmail;
export const appStoreUrl: string | null = config.appStoreUrl;
export const googlePlayUrl: string | null = config.googlePlayUrl;

export function macDownloadUrl(version: string = desktopVersion): string {
  return `${config.downloadBaseUrl}/${version}/ShellX-${version}.dmg`;
}

export function windowsDownloadUrl(version: string = desktopVersion): string {
  return `${config.downloadBaseUrl}/${version}/ShellX-Setup-${version}.exe`;
}
