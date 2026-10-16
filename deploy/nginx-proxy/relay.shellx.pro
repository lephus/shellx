# nginx-proxy settings for relay.shellx.pro (VPS spec §3), included in its server block. Lives in
# ~/phu/shellx/nginx-proxy/ and is copied once into nginx-proxy's vhost.d (deploy/README.md, step 5).
# No access log: the privacy policy promises that requests (and client IPs) are not logged.
access_log off;
# Clients ping every 30 s; idle WebSockets must survive well past that.
proxy_read_timeout 120s;
proxy_send_timeout 120s;
# The relay caps JSON bodies at 16 KiB (413 with its own error code); stop anything far bigger here.
client_max_body_size 32k;
