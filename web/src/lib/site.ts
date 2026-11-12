import config from '../site.config.json';

// The single source of truth for download and store links is src/site.config.json.
// Installer file names must match what release-desktop.yml uploads to download.shellx.pro:
//   desktop/<version>/ShellX-<version>.dmg
//   desktop/<version>/ShellX-Setup-<version>.exe
export const desktopVersion: string = config.desktopVersion;
export const supportEmail: string = config.supportEmail;
/** Public contact channel on the website; the email stays for legal requests (privacy, terms). */
export const discordUrl: string = config.discordUrl;
/**
 * SHA-256 of the Windows installer for `desktopVersion`, filled at release from the SHA256SUMS file
 * (64 hex characters). `null` or anything else shows no checksum. Lower-cased here.
 */
export const windowsSha256: string | null = (() => {
  const value = config.windowsSha256;
  return typeof value === 'string' && /^[0-9a-fA-F]{64}$/.test(value.trim()) ? value.trim().toLowerCase() : null;
})();
export const appStoreUrl: string | null = config.appStoreUrl;
export const googlePlayUrl: string | null = config.googlePlayUrl;
/** Origin of the ShellX API that mints share-viewer tickets (`POST /v2/shares/:id/ticket`). */
export const shareApiBase: string = config.shareApiBase;

export function macDownloadUrl(version: string = desktopVersion): string {
  return `${config.downloadBaseUrl}/${version}/ShellX-${version}.dmg`;
}

export function windowsDownloadUrl(version: string = desktopVersion): string {
  return `${config.downloadBaseUrl}/${version}/ShellX-Setup-${version}.exe`;
}
