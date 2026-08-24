#!/bin/bash
set -euo pipefail

# Nightly: dump, encrypt, upload, report. Encryption is asymmetric on purpose —
# this container holds only the public recipient key, so whoever takes this host
# gets the live database but cannot read a single archived dump.
source /etc/backup.env

# Any failure below reports immediately. The dead-man's switch on the other side
# catches the case this cannot: the job never running at all.
trap 'curl -fsS -m 10 "${HEALTHCHECK_URL}/fail" > /dev/null || true' ERR

export PGPASSWORD="$POSTGRES_PASSWORD"
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"
# R2 rejects the streaming checksum trailers recent AWS CLI versions send by
# default; without these two the upload fails with an opaque signature error.
export AWS_REQUEST_CHECKSUM_CALCULATION="when_required"
export AWS_RESPONSE_CHECKSUM_VALIDATION="when_required"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
target="s3://${R2_BUCKET}/${BACKUP_PREFIX}/maney-${stamp}.dump.age"

# Custom format: already compressed, and the only format pg_restore accepts for
# selective restores.
pg_dump --format=custom --no-owner --no-privileges \
        --host "$PGHOST" --username "$PGUSER" "$PGDATABASE" \
  | age --recipient "$AGE_RECIPIENT" \
  | aws s3 cp - "$target" --endpoint-url "$R2_ENDPOINT"

curl -fsS -m 10 "$HEALTHCHECK_URL" > /dev/null
echo "backed up to ${target}"
