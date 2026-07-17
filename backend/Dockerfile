# S4 / Swift runtime deploy image for the Time of Life backend.
# Build:  docker build -t timeoflife-backend .
# Run:    docker run --rm -p 8080:8080 --env-file .env timeoflife-backend
FROM swift:6.0-bookworm AS build
WORKDIR /app
# Cache dependencies first.
COPY Package.swift ./
RUN swift package resolve \
    && cp -R .build/checkouts ./checkouts-cache || true
# Copy source.
COPY Sources ./Sources
COPY Tests ./Tests
# Build a release executable.
RUN swift build -c release --static-swift-stdlib || swift build -c release

FROM swift:6.0-bookworm-slim AS run
WORKDIR /app
# Copy the built executable(s). The executable target is named "App".
COPY --from=build /app/.build/release/App /usr/local/bin/app
# Expose Vapor's default port.
EXPOSE 8080
ENTRYPOINT ["app"]