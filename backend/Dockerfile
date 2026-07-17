# S4 / Go runtime deploy image for the Time of Life backend.
# Build:  docker build -t timeoflife-backend .
# Run:    docker run --rm -p 8080:8080 --env-file .env timeoflife-backend
FROM golang:1.22-bookworm AS build
WORKDIR /src
# Cache dependencies first.
COPY go.mod go.sum ./
RUN go mod download
# Copy source.
COPY cmd ./cmd
COPY internal ./internal
# Build a static release binary named "server".
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot AS run
WORKDIR /app
COPY --from=build /out/server /server
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/server"]