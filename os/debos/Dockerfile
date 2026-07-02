ARG DEBOS_BASE_IMAGE=docker.io/godebos/debos:v1.1.6
FROM ${DEBOS_BASE_IMAGE}

ARG RUGIX_VERSION=v1.3.0-dev.2

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install --no-install-recommends -y \
        bmap-tools \
        ca-certificates \
        curl \
        jq \
        zstd; \
    rm -rf /var/lib/apt/lists/*

RUN curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \
    | sh -s -- -b /usr/local/bin

RUN set -eux; \
    case "$(uname -m)" in \
        x86_64|amd64) triple="x86_64-unknown-linux-musl" ;; \
        aarch64|arm64) triple="aarch64-unknown-linux-musl" ;; \
        *) echo "unsupported container architecture: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL \
        "https://github.com/rugix/rugix/releases/download/${RUGIX_VERSION}/binaries-${triple}.tar" \
        -o /tmp/rugix-binaries.tar; \
    tar -xf /tmp/rugix-binaries.tar \
        -C /usr/local/bin \
        --strip-components=1 \
        ./rugix-bundler; \
    rm /tmp/rugix-binaries.tar
