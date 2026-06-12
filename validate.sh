#!/bin/bash
# ================================================================================================
# Script Name: validate.sh
# ================================================================================================
# Purpose:
#   Validates that the Resume Scorer (Go) is reachable over HTTPS and
#   responding. Polls the sign-in page until HTTP 200 is received.
#   Fargate tasks need time to start, run AutoMigrate, seed, and join the ALB.
# ================================================================================================

MAX_ATTEMPTS=40
SLEEP_SECONDS=15
APP_URL="https://myjobs-ror.mikes-cloud-solutions.com/signin"

echo "NOTE: Waiting for ${APP_URL} to return HTTP 200..."

# ------------------------------------------------------------------------------
# Poll Until Healthy
# ------------------------------------------------------------------------------
for ((i=1; i<=MAX_ATTEMPTS; i++)); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 5 \
    "${APP_URL}" 2>/dev/null || echo "000")

  if [ "$STATUS" = "200" ]; then
    echo "NOTE: Resume Scorer is healthy (HTTP 200)."
    echo "NOTE: URL: https://myjobs-ror.mikes-cloud-solutions.com"
    echo "NOTE: Demo login: demo@example.com / password123"
    exit 0
  fi

  echo "WARNING: Attempt ${i}/${MAX_ATTEMPTS}: HTTP ${STATUS} — retry in ${SLEEP_SECONDS}s"
  sleep "${SLEEP_SECONDS}"
done

echo "ERROR: Timed out. Check ECS logs in CloudWatch (/ecs/resumescorer)."
exit 1

# ================================================================================================
# End of Script
# ================================================================================================
