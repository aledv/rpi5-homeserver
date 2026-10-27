FROM alpine:3.22
RUN apk add --no-cache apcupsd curl tzdata
COPY ups-notify.sh /usr/local/bin/ups-notify.sh
CMD ["/usr/local/bin/ups-notify.sh"]
