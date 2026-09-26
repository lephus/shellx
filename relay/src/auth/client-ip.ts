import { BlockList, isIP } from "node:net";

/**
 * Peers allowed to tell us the client address in `X-Real-IP`: loopback and private networks, which
 * is where nginx-proxy connects from (the relay container publishes no port). A request that
 * reaches the relay from anywhere else cannot choose its own rate-limit key (Review Focus 4).
 */
const TRUSTED_PEERS = new BlockList();
TRUSTED_PEERS.addSubnet("127.0.0.0", 8, "ipv4");
TRUSTED_PEERS.addSubnet("10.0.0.0", 8, "ipv4");
TRUSTED_PEERS.addSubnet("172.16.0.0", 12, "ipv4");
TRUSTED_PEERS.addSubnet("192.168.0.0", 16, "ipv4");
TRUSTED_PEERS.addSubnet("100.64.0.0", 10, "ipv4");
TRUSTED_PEERS.addAddress("::1", "ipv6");
TRUSTED_PEERS.addSubnet("fc00::", 7, "ipv6");

/** `::ffff:10.0.0.5` → `10.0.0.5`; anything else unchanged. */
function unmapped(address: string): string {
  const match = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/i.exec(address);
  return match ? match[1]! : address;
}

function isTrustedPeer(address: string): boolean {
  const family = isIP(address);
  return family !== 0 && TRUSTED_PEERS.check(address, family === 4 ? "ipv4" : "ipv6");
}

/**
 * The client address used as the rate-limit key (spec §4.2): `X-Real-IP` set by nginx-proxy when
 * the TCP peer is a trusted proxy and the header holds a valid IP, otherwise the peer address
 * itself. Used only in memory by the limiters; never logged.
 */
export function clientIp(realIpHeader: string | undefined, remoteAddress: string | undefined): string {
  const peer = remoteAddress === undefined ? undefined : unmapped(remoteAddress);
  if (peer !== undefined && isTrustedPeer(peer)) {
    const forwarded = realIpHeader?.trim();
    if (forwarded !== undefined && isIP(forwarded) !== 0) return unmapped(forwarded);
  }
  return peer ?? "unknown";
}
