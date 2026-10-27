# Stage 1: Build
FROM golang:1.24-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
ARG VERSION=?
ARG SHA=?
# Constrain build-identity args to a safe charset before interpolating them
# into -ldflags: git ref names may legally contain shell metacharacters.
RUN case "$VERSION$SHA" in *[!0-9A-Za-z./_?-]*) echo "unsafe VERSION/SHA build arg" >&2; exit 1 ;; esac && \
    CGO_ENABLED=0 GOOS=linux go build -ldflags "-X main.version=$VERSION -X main.sha=$SHA" -o /app/server ./cmd/server

# Stage 2: Run
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app
COPY --from=builder /app/server .

EXPOSE 8080

CMD ["./server"]
