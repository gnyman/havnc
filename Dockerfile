FROM alpine:3.19

LABEL AboutImage "Home Assistant Dashboard trough VNC"

#Locale
ENV LANG=en_US.UTF-8 \
	LANGUAGE=en_US.UTF-8 \
	LC_ALL=C.UTF-8 \
	TZ="UTC"

RUN	apk update && \
	apk add --no-cache tzdata ca-certificates supervisor curl chromium wget openssl bash python3 py3-requests sed unzip xvfb tigervnc websockify openbox luakit nss alsa-lib font-noto font-noto-cjk jq git procps

# TimeZone
RUN	cp /usr/share/zoneinfo/$TZ /etc/localtime && \
	echo $TZ > /etc/timezone

ARG NOVNC_VERSION=v0.5.1
RUN git clone -c http.sslVerify=false --branch $NOVNC_VERSION https://github.com/novnc/noVNC.git /opt/novnc

# Wipe Temp Files
RUN	apk del build-base curl wget unzip tzdata openssl && \
	rm -rf /var/cache/apk/* /tmp/*


COPY index.html /opt/novnc/index.html
COPY config /config
RUN mkdir -p /root/.config/tigervnc

ENV VNC_TITLE="Home Assistant Dashboard" \
#Local Display Server Port
DISPLAY=:0 \
#NoVNC Port
NOVNC_PORT=$PORT \
PORT=8080

CMD ["supervisord", "-l", "/var/log/supervisord.log", "-c","/config/supervisord.conf"]
