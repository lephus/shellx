# nginx-proxy settings for relay.shellx.pro (VPS spec §3), included in its server block. Lives in
# ~/phu/shellx/nginx-proxy/ and is copied once into nginx-proxy's vhost.d (deploy/README.md, step 5).
# No access log: the privacy policy promises that requests (and client IPs) are not logged.
access_log off;
# v1 clients ping every 30 s; idle WebSockets must survive well past that. 330 s is above cmux-relay's
# 300 s circuit idle timeout (v2), so it closes idle circuits itself, not nginx. This file applies to
# the whole server block, so both the v1 and the /v2/relay locations.
proxy_read_timeout 330s;
proxy_send_timeout 330s;
# The relay caps JSON bodies at 16 KiB (413 with its own error code); stop anything far bigger here.
client_max_body_size 32k;
