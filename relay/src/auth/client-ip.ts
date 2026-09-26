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
 * The /64 network of an IPv6 address, e.g. `2001:db8:1:2::/64` for `2001:0DB8:1:2:a::1`. One
 * subscriber is usually given a whole /64, so keying by the full address would let a single client
 * rotate through 2^64 keys and never be limited (M12). `address` must be a valid IPv6 address.
 */
function ipv6Network64(address: string): string {
  let text = address.split("%")[0]!.toLowerCase(); // drop a zone index (fe80::1%eth0)
  const dotted = /(\d+)\.(\d+)\.(\d+)\.(\d+)$/.exec(text); // trailing IPv4 (64:ff9b::198.51.100.7)
  if (dotted) {
    const [a, b, c, d] = dotted.slice(1).map(Number) as [number, number, number, number];
    text = `${text.slice(0, dotted.index)}${((a << 8) | b).toString(16)}:${((c << 8) | d).toString(16)}`;
  }
  const [head = "", tail] = text.split("::");
  const headGroups = head === "" ? [] : head.split(":");
  const tailGroups = tail === undefined || tail === "" ? [] : tail.split(":");
  const zeros = tail === undefined ? [] : Array<string>(8 - headGroups.length - tailGroups.length).fill("0");
  const groups = [...headGroups, ...zeros, ...tailGroups].map((group) => parseInt(group, 16).toString(16));
  return `${groups.slice(0, 4).join(":")}::/64`;
}

/** The rate-limit key of a valid address: IPv4 as is, IPv4-mapped IPv6 as IPv4, other IPv6 by its /64. */
function limitKey(address: string): string {
  const plain = unmapped(address);
  return isIP(plain) === 6 ? ipv6Network64(plain) : plain;
}

/**
 * The client key used by the rate limiters (spec §4.2): the address in `X-Real-IP` set by
 * nginx-proxy when the TCP peer is a trusted proxy and the header holds a valid IP, otherwise the
 * peer address itself; an IPv6 address is reduced to its /64. Used only in memory by the limiters;
 * never logged.
 */
export function clientIp(realIpHeader: string | undefined, remoteAddress: string | undefined): string {
  const peer = remoteAddress === undefined ? undefined : unmapped(remoteAddress);
  if (peer !== undefined && isTrustedPeer(peer)) {
    const forwarded = realIpHeader?.trim();
    if (forwarded !== undefined && isIP(forwarded) !== 0) return limitKey(forwarded);
  }
  return peer === undefined ? "unknown" : isIP(peer) === 0 ? peer : limitKey(peer);
}
