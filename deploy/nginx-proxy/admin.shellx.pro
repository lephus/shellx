# nginx-proxy settings for admin.shellx.pro (the relay's admin dashboard), included in its server
# block. Lives in ~/phu/shellx/nginx-proxy/ and is copied once into nginx-proxy's vhost.d
# (deploy/README.md, step 5 and "Admin").
# No access log: the privacy policy promises that requests (and client IPs) are not logged.
access_log off;
# The admin API's bodies are tiny (a password, two versions); the relay caps JSON at 16 KiB anyway.
client_max_body_size 16k;
