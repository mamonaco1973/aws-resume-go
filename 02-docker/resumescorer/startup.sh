#!/bin/sh
# ================================================================================
# startup.sh — Container Entrypoint
# ================================================================================
# The Go binary handles DB connection retries, AutoMigrate, seeding, the
# Asynq worker goroutine, and the HTTP server — all in one process.
# startup.sh exists solely to match the deployment entrypoint convention and
# allow pre-flight environment checks to be added here in future.
# ================================================================================

set -e

echo "NOTE: Starting Resume Scorer (Go)..."
exec /app/resumescorer
