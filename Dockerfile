FROM python:3.11-alpine

RUN apk add --no-cache su-exec \
    && addgroup -S app \
    && adduser -S -G app app

WORKDIR /app

COPY url-probe/probe.py .
COPY entrypoint.sh run.sh ./

RUN chmod +x entrypoint.sh run.sh \
    && echo '* * * * * /app/run.sh >> /proc/1/fd/1 2>&1' > /etc/crontabs/root

ENV PROBE_TIMEOUT=5
ENV PROBE_OUTPUT_DIR=/textfile

ENTRYPOINT ["/app/entrypoint.sh"]
