#!/bin/sh
set -e

# Apply any pending Prisma migrations before the server accepts traffic.
# `migrate deploy` is idempotent: on a fresh database it applies every
# migration in order; on an existing one it applies only what is pending.
# If migrations fail, the container exits (no exec) so the orchestrator
# restarts it / surfaces the failure instead of serving traffic against
# an un-migrated schema.
echo "[entrypoint] running prisma migrate deploy..."
npx prisma migrate deploy

echo "[entrypoint] migrations up to date, starting server..."
exec "$@"
