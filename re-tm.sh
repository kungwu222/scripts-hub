#!/usr/bin/env bash
set -Eeuo pipefail

# =========================================================
# VPS guaji script
# OS support: Debian 11 above、Ubuntu 20.04 above
# Archi support: AMD64/x86_64、ARM64/aarch64
# =========================================================

if [[ $EUID -ne 0 ]]; then
    echo "Please run script with root or sudo command!"
    exit 1
fi

# -------------------------
# Configuration
# -------------------------

TM_TOKEN="0AzuB/AnC//4yBTrwUrGmMXX/qaFIg2b8C+47K/P2lU="

TM_IMAGE_AMD64="traffmonetizer/cli_v2"
TM_IMAGE_ARM64="traffmonetizer/cli_v2:arm64v8"

# -------------------------
# Check OS version
# -------------------------

if [[ ! -f /etc/os-release ]]; then
    echo "unKnown OS!"
    exit 1
fi

source /etc/os-release

version_ge() {
    dpkg --compare-versions "$1" ge "$2"
}

case "$ID" in
    debian)
        if ! version_ge "$VERSION_ID" "11"; then
            echo "Not support Debian version: $VERSION_ID"
            echo "Require Debian 11 or above!"
            exit 1
        fi
        ;;
    ubuntu)
        if ! version_ge "$VERSION_ID" "20.04"; then
            echo "Not support Ubuntu version: $VERSION_ID"
            echo "Require Ubuntu 20.04 or above!"
            exit 1
        fi
        ;;
    *)
        echo "Not support OS：$ID $VERSION_ID"
        echo "Only support Debian 11+ or Ubuntu 20.04+ !"
        exit 1
        ;;
esac

echo "OS detected: $PRETTY_NAME"

# -------------------------
# Check CPU Architecture
# -------------------------

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64)
        TM_IMAGE="$TM_IMAGE_AMD64"
        echo "CPU Arch: AMD64"
        ;;
    aarch64|arm64)
        TM_IMAGE="$TM_IMAGE_ARM64"
        echo "CPU Arch: ARM64"
        ;;
    *)
        echo "Not support CPU Arch: $ARCH"
        exit 1
        ;;
esac

echo "TraffMonetizer image: $TM_IMAGE"

# -------------------------
# Install Docker
# -------------------------

install_docker() {
    echo "Installing Docker..."

    apt-get update

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker.io \
        ca-certificates \
        curl

    systemctl enable docker
    systemctl start docker

    echo "Docker install successful!"
}

if ! command -v docker >/dev/null 2>&1; then
    install_docker
else
    echo "Docker has been installed, skipped!"
    systemctl enable docker
    systemctl start docker
fi

if ! docker info >/dev/null 2>&1; then
    echo "Docker service unavailable!"
    exit 1
fi

# -------------------------
# Create container func
# if the same one existed, delete it and re-create it
# -------------------------

create_container() {
    local container_name="$1"
    shift

    if docker container inspect "$container_name" >/dev/null 2>&1; then
        echo "Found the container existed: $container_name"
        echo "Stop and deleted: $container_name"

        docker rm -f "$container_name" >/dev/null
    fi

    echo "Creating container: $container_name"
    docker run -d "$@" >/dev/null

    echo "Create container done: $container_name"
}

# -------------------------
# Check and pull image
# Only pull it if not existed in local
# -------------------------

pull_if_missing() {
    local image="$1"

    if docker image inspect "$image" >/dev/null 2>&1; then
        echo "Image has existed, skip pulling: $image"
    else
        echo "Image doesn't existed, start pulling: $image"
        docker pull "$image"
    fi
}

echo "checking Docker image..."

pull_if_missing "$TM_IMAGE"

# -------------------------
# TraffMonetizer
# -------------------------

create_container "tm" \
    --restart=always \
    --name tm \
    "$TM_IMAGE" \
    start accept \
    --token "$TM_TOKEN"

# -------------------------
# Watchtower
# -------------------------

if docker container inspect watchtower >/dev/null 2>&1; then
    echo "Watchtower has existed, re-creating it..."

    docker rm -f watchtower >/dev/null
fi

docker run -d \
    --restart=always \
    --name watchtower \
    -v /var/run/docker.sock:/var/run/docker.sock \
    containrrr/watchtower \
    --cleanup \
    --interval 86400 \
    earnfm-client tm repocket

# -------------------------
# Finish
# -------------------------

echo
echo "=========================================="
echo "tm service done!"
echo "=========================================="
echo
echo "container status:"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
echo
echo "Watchtower: check image update per 24 hours."
