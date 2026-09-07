#!/usr/bin/env bash
set -euo pipefail

# PayFlex Sandbox Keep-Alive Script
# Sends periodic health pings to prevent Freebuff Cloud sandbox idle-timeout

SANDBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_PORT="${API_PORT:-3000}"
HEALTH_ENDPOINT="http://localhost:${API_PORT}/health"
PING_ENDPOINT="http://localhost:${API_PORT}/api/v1/bmoni/ping"
LOG_FILE="${SANDBOX_DIR}/keepalive.log"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "[${TIMESTAMP}] Executing sandbox keep-alive ping..." >> "${LOG_FILE}"

HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${HEALTH_ENDPOINT}" || echo "000")

if [ "${HEALTH_STATUS}" -eq 200 ]; then
    echo "[${TIMESTAMP}] Sandbox HEALTH OK (200)" >> "${LOG_FILE}"
    
    # Send secondary BMONI gateway check ping
    BMONI_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${PING_ENDPOINT}" || echo "000")
    echo "[${TIMESTAMP}] BMONI Gateway Ping HTTP ${BMONI_STATUS}" >> "${LOG_FILE}"
else
    echo "[${TIMESTAMP}] WARNING: Health check failed with status ${HEALTH_STATUS}. Triggering restart..." >> "${LOG_FILE}"
    bash "${SANDBOX_DIR}/startup.sh" >> "${LOG_FILE}" 2>&1 || echo "[${TIMESTAMP}] ERROR: Recovery failed." >> "${LOG_FILE}"
fi
