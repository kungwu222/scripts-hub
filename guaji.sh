#!/usr/bin/env bash
set -Eeuo pipefail

# =========================================================
# VPS guaji script
# Support OS: Debian 11 above、Ubuntu 20.04 above
# Support arch: AMD64/x86_64、ARM64/aarch64
# =========================================================

if [[ $EUID -ne 0 ]]; then
    echo "Please run script with root or sudo command!"
    exit 1
fi

# -------------------------
# Configration
# -------------------------

EARNFM_TOKEN="4d26575e-8516-42da-aa8b-ccd707b70741"

TM_TOKEN="0AzuB/AnC//4yBTrwUrGmMXX/qaFIg2b8C+47K/P2lU="

RP_EMAIL="firework08@freeyou.eu.org"
RP_API_KEY="388b7b58-94af-4c05-a1f3-ac651cc868d6"

EARNFM_IMAGE="earnfm/earnfm-client:latest"
TM_IMAGE_AMD64="traffmonetizer/cli_v2"
TM_IMAGE_ARM64="traffmonetizer/cli_v2:arm64v8"
REPOCKET_IMAGE="repocket/repocket"

# -------------------------
# Check OS Edition
# -------------------------

if [[ ! -f /etc/os-release ]]; then
    echo "Can not figure out the OS!"
    exit 1
fi

source /etc/os-release

version_ge() {
    dpkg --compare-versions "$1" ge "$2"
}

case "$ID" in
    debian)
        if ! version_ge "$VERSION_ID" "11"; then
            echo "Doesn't support Debian version: $VERSION_ID"
            echo "Required Debian 11 or above."
            exit 1
        fi
        ;;
    ubuntu)
        if ! version_ge "$VERSION_ID" "20.04"; then
            echo "Doesn't support Ubuntu version: $VERSION_ID"
            echo "Required Ubuntu 20.04 or above."
            exit 1
        fi
        ;;
    *)
        echo "Doesn't support this OS: $ID $VERSION_ID"
        echo "Only support Debian 11+ 和 Ubuntu 20.04+"
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
        echo "Doesn't support CPU Arch: $ARCH"
        exit 1
        ;;
esac

echo "TraffMonetizer Image: $TM_IMAGE"

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

    echo "Docker install successful"
}

if ! command -v docker >/dev/null 2>&1; then
    install_docker
else
    echo "Docker already installed, skipped"
    systemctl enable docker
    systemctl start docker
fi

if ! docker info >/dev/null 2>&1; then
    echo "Docker not available"
    exit 1
fi

# -------------------------
# Create docker container
# if existed containers using the same image, delete them and re-create it
# -------------------------

remove_containers_by_image() {
    local image="$1"
    local existing_container

    while IFS= read -r existing_container; do
        if [[ -n "$existing_container" ]]; then
            echo "Existing Container for image $image: $existing_container"
            echo "Stop and delete: $existing_container"
            docker rm -f "$existing_container" >/dev/null
        fi
    done < <(docker ps -a --filter "ancestor=$image" --format '{{.Names}}')
}

create_container() {
    local container_name="$1"
    local image="$2"
    shift 2

    remove_containers_by_image "$image"

    if docker container inspect "$container_name" >/dev/null 2>&1; then
        echo "Existing Container: $container_name"
        echo "Stop and delete: $container_name"

        docker rm -f "$container_name" >/dev/null
    fi

    echo "Creating container: $container_name"
    docker run -d "$@" >/dev/null

    echo "Container created: $container_name"
}

# -------------------------
# check and pull image
# only pull it if not existed in local
# -------------------------

pull_if_missing() {
    local image="$1"

    if docker image inspect "$image" >/dev/null 2>&1; then
        echo "Image existed, skip pull: $image"
    else
        echo "Start to pull image: $image"
        docker pull "$image"
    fi
}

echo "Checking Docker image..."

pull_if_missing "$EARNFM_IMAGE"
pull_if_missing "$TM_IMAGE"
pull_if_missing "$REPOCKET_IMAGE"

# -------------------------
# EarnFM
# -------------------------

create_container "earnfm-client" \
    "$EARNFM_IMAGE" \
    --restart=always \
    --name earnfm-client \
    -e "EARNFM_TOKEN=$EARNFM_TOKEN" \
    "$EARNFM_IMAGE"

# -------------------------
# TraffMonetizer
# -------------------------

create_container "tm" \
    "$TM_IMAGE" \
    --restart=always \
    --name tm \
    "$TM_IMAGE" \
    start accept \
    --token "$TM_TOKEN"

# -------------------------
# Repocket
# -------------------------

create_container "repocket" \
    "$REPOCKET_IMAGE" \
    --restart=always \
    --name repocket \
    -e "RP_EMAIL=$RP_EMAIL" \
    -e "RP_API_KEY=$RP_API_KEY" \
    "$REPOCKET_IMAGE"

# -------------------------
# Watchtower
# -------------------------

if docker container inspect watchtower >/dev/null 2>&1; then
    echo "Watchtower existed re-created it to ensure the configuration is correct."

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
echo "earnfm-client tm repocket services are running!"
echo "=========================================="
echo
echo "Docker container status:"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
echo
echo "Watchtower: check image update per 24 hours."
