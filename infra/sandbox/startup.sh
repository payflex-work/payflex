#!/usr/bin/env bash
set -euo pipefail

# PayFlex Sandbox Startup & Recovery Checklist Script
# Reliably recovers Freebuff Cloud sandbox from SANDBOX_NOT_RUNNING state

echo "=========================================="
echo "   PayFlex Sandbox Recovery & Startup    "
echo "=========================================="

SANDBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_PORT="${API_PORT:-3000}"
HEALTH_URL="http://localhost:${API_PORT}/health"

echo "[1/4] Checking environment configuration..."
if [ -f "${SANDBOX_DIR}/.env" ]; then
    source "${SANDBOX_DIR}/.env"
    echo "  -> Environment loaded from ${SANDBOX_DIR}/.env"
else
    echo "  -> Warning: No .env file found in ${SANDBOX_DIR}. Using default environment."
fi

echo "[2/4] Verifying base dependencies (Docker / PostgreSQL / Node)..."
if command -v docker >/dev/null 2>&1; then
    echo "  -> Docker detected. Starting containers..."
    docker-compose -f "${SANDBOX_DIR}/docker-compose.sandbox.yml" up -d postgres redis || true
fi

echo "[3/4] Testing API server connectivity..."
RETRY_COUNT=0
MAX_RETRIES=10
SUCCESS=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s -f "$HEALTH_URL" > /dev/null 2>&1; then
        SUCCESS=1
        break
    fi
    echo "  -> API not responding yet. Retrying in 2 seconds... ($((RETRY_COUNT + 1))/$MAX_RETRIES)"
    sleep 2
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

if [ $SUCCESS -eq 1 ]; then
    echo "[4/4] Sandbox successfully restored and healthy at $HEALTH_URL"
    exit 0
else
    echo "[ERROR] API server failed to respond within time limit."
    echo "Check server logs or run: docker-compose -f ${SANDBOX_DIR}/docker-compose.sandbox.yml logs api"
    exit 1
fi
