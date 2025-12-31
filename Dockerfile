FROM alpine:3.20

RUN apk add --no-cache bash curl tzdata iproute2 ca-certificates \
  && addgroup -S dcs \
  && adduser -S -G dcs dcs

WORKDIR /app
COPY client_checkin.sh /app/client_checkin.sh
RUN chmod 755 /app/client_checkin.sh

USER dcs

ENTRYPOINT ["/app/client_checkin.sh"]
