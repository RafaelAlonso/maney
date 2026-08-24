#!/bin/sh
set -eu

# busybox cron runs a job with an almost empty environment: every variable the
# Kamal accessory sets would be blank at 03:00, and the backup would fail
# silently every single night. Freeze them here, where they still exist, and
# have the job source them back.
export -p > /etc/backup.env
chmod 600 /etc/backup.env

exec crond -f -l 2
