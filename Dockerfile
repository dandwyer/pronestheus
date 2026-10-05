# This Dockerfile is intended to be used with goreleaser.
# It doesn't build the executable, it expects it to be already built by the goreleaser.
# Base image is Docker Hardened Images' "static" image (Debian 13): a minimal,
# distroless-style runtime for statically-linked binaries. It ships the CA
# certificates and timezone data needed for the Nest/OpenWeatherMap HTTPS calls
# and runs as UID 65532 (nonroot) by default.
# https://dhi.io/catalog/static

FROM dhi.io/static:20250419-debian13
COPY pronestheus /
EXPOSE 9777
ENTRYPOINT ["/pronestheus"]
