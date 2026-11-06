# Containerfile builds the normal Linux executable for local Podman development, for the
# aarch64/x86_64 installer archives and for the image the release workflow publishes to
# ghcr.io/tysee/garmin-stride. The runtime contains only the binary and non-secret configuration.
# Base images are pinned to multi-arch manifest indexes so --platform selects the matching layers.
FROM docker.io/library/rust:1.99.1-bookworm@sha256:48b7f435b8fc6378ce43b44f15e3a47fd8919b2825f835c39bd4bd3da50af5b8 AS build
WORKDIR /build
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY migrations ./migrations
COPY config.example.toml ./
COPY deploy/Caddyfile ./deploy/Caddyfile
RUN --mount=type=cache,id=garmin-stride-registry,target=/usr/local/cargo/registry \
    mkdir -p /data /out && chmod 700 /data && cargo build --release --locked --bin stride && cp target/release/stride /out/stride

FROM gcr.io/distroless/cc-debian12:nonroot@sha256:9dac0a79194e45a7da0158a9c6da57b217585af0786db3845d1f0ec1a0dd182f
# Links the image published to ghcr.io by the release workflow to this repository.
LABEL org.opencontainers.image.source="https://github.com/tysee/garmin-stride"
WORKDIR /app
COPY --from=build /out/stride /app/stride
COPY config.container.toml /app/config.toml
COPY --from=build --chown=65532:65532 /data /data
USER 65532:65532
VOLUME ["/data"]
EXPOSE 8080
ENTRYPOINT ["/app/stride", "--config", "/app/config.toml"]
CMD ["serve", "--transport", "http"]
