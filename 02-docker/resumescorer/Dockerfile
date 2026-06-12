# ================================================================================
# Resume Scorer Go Application — Multi-Stage Docker Build
# ================================================================================
# Stage 1 (builder): compile the Go binary with all dependencies resolved.
# Stage 2 (runtime): copy only the binary and startup.sh into a minimal
# Alpine image. Result is ~20 MB vs ~800 MB for the Rails equivalent.
# ================================================================================

# ================================================================================
# Stage 1 — Build
# ================================================================================
FROM golang:1.22-alpine AS builder

WORKDIR /build

# Copy all source first so go mod tidy can resolve imports from the code.
# This differs from the classic "copy go.mod first" pattern but is required
# here because go.sum may not exist on a fresh clone — tidy generates it.
COPY . .

# tidy generates/updates go.sum, download fetches all modules into the
# module cache, then build compiles the static binary.
RUN go mod tidy && go mod download

# CGO_ENABLED=0 produces a fully static binary with no libc dependency so
# the runtime image can be stripped down to Alpine with no extra libraries.
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o resumescorer .

# ================================================================================
# Stage 2 — Runtime
# ================================================================================
FROM alpine:3.19

# ca-certificates: needed for TLS connections to AWS (Bedrock, S3, Secrets Manager)
# curl: used by startup.sh health check
RUN apk add --no-cache ca-certificates curl

WORKDIR /app

COPY --from=builder /build/resumescorer .
COPY startup.sh .
RUN chmod +x startup.sh

EXPOSE 3000

ENTRYPOINT ["./startup.sh"]
