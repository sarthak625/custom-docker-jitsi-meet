ARG JITSI_REPO=jitsi
FROM ${JITSI_REPO}/base

RUN \
	apt-dpkg-wrap apt-get update && \
	apt-dpkg-wrap apt-get install -y cron nginx-extras jitsi-meet-web && \
	apt-dpkg-wrap apt-get install -y -t stretch-backports certbot && \
	apt-cleanup && \
	rm -f /etc/nginx/conf.d/default.conf && \
	rm -f /usr/share/jitsi-meet/interface_config.js

COPY rootfs/ /

EXPOSE 80 443

VOLUME ["/config", "/etc/letsencrypt"]

# Copy the modified app bundle
COPY custom/watermark.png /usr/share/jitsi-meet/images/watermark.png
COPY custom/favicon.ico /usr/share/jitsi-meet/favicon.ico
COPY custom/favicon.ico /usr/share/jitsi-meet/images/favicon.ico
COPY custom/app.bundle.min.js /usr/share/jitsi-meet/libs/app.bundle.min.js

# COPY custom/index.html /usr/share/jitsi-meet/index.html
# COPY custom/all.css /usr/share/jitsi-meet/css/all.css
