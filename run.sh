#!/bin/sh

. /app/probe-env.sh

exec su-exec app python /app/probe.py /config/urls.txt
