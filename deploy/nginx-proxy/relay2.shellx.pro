# nginx-proxy settings for relay2.shellx.pro (fallback host of relay2, deploy/README.md "Relay v2"),
# included in its server block; copied into nginx-proxy's vhost.d like the others.
# No access log: the privacy policy promises that requests (and client IPs) are not logged.
access_log off;
# Above cmux-relay's 300 s circuit idle timeout, so it closes idle circuits itself, not nginx.
proxy_read_timeout 330s;
proxy_send_timeout 330s;
