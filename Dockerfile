# This Dockerfile is intended to be used with goreleaser.
# It doesn't build the executable, it expects it to be already built by the goreleaser.
# Base image is Google's distroless "static" image (actively maintained), which ships
# CA certificates and timezone data needed for the Nest/OpenWeatherMap HTTPS calls.
# The "nonroot" variant runs as UID 65532 by default.

FROM gcr.io/distroless/static-debian13:nonroot
COPY pronestheus /
EXPOSE 9777
ENTRYPOINT ["/pronestheus"]
