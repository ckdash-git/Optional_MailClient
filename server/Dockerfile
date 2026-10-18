# syntax=docker/dockerfile:1
FROM golang:1.26-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/master ./cmd/master \
 && ./scripts/check-licenses.sh /out/THIRD_PARTY_NOTICES.txt

# Static binary, no shell, no package manager, runs as uid 65532.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/master /master
COPY --from=build /out/THIRD_PARTY_NOTICES.txt /THIRD_PARTY_NOTICES.txt
ENV MASTER_DB=/data/master.db
VOLUME ["/data"]
EXPOSE 8443
USER 65532:65532
ENTRYPOINT ["/master"]
