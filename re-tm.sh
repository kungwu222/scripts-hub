#!/usr/bin/env bash
set -Eeuo pipefail

# =========================================================
# VPS 挂机脚本
# 支持：Debian 11 above、Ubuntu 20.04 above
# 支持：AMD64/x86_64、ARM64/aarch64
# =========================================================

if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 或 sudo 执行此脚本"
    exit 1
fi

# -------------------------
# 配置区域
# -------------------------

TM_TOKEN="0AzuB/AnC//4yBTrwUrGmMXX/qaFIg2b8C+47K/P2lU="

TM_IMAGE_AMD64="traffmonetizer/cli_v2"
TM_IMAGE_ARM64="traffmonetizer/cli_v2:arm64v8"

# -------------------------
# 检查系统版本
# -------------------------

if [[ ! -f /etc/os-release ]]; then
    echo "无法识别操作系统"
    exit 1
fi

source /etc/os-release

version_ge() {
    dpkg --compare-versions "$1" ge "$2"
}

case "$ID" in
    debian)
        if ! version_ge "$VERSION_ID" "11"; then
            echo "不支持的 Debian 版本：$VERSION_ID"
            echo "要求 Debian 11 或更高版本"
            exit 1
        fi
        ;;
    ubuntu)
        if ! version_ge "$VERSION_ID" "20.04"; then
            echo "不支持的 Ubuntu 版本：$VERSION_ID"
            echo "要求 Ubuntu 20.04 或更高版本"
            exit 1
        fi
        ;;
    *)
        echo "不支持的操作系统：$ID $VERSION_ID"
        echo "支持 Debian 11+ 和 Ubuntu 20.04+"
        exit 1
        ;;
esac

echo "检测到系统：$PRETTY_NAME"

# -------------------------
# 检查 CPU 架构
# -------------------------

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64)
        TM_IMAGE="$TM_IMAGE_AMD64"
        echo "CPU 架构：AMD64"
        ;;
    aarch64|arm64)
        TM_IMAGE="$TM_IMAGE_ARM64"
        echo "CPU 架构：ARM64"
        ;;
    *)
        echo "不支持的 CPU 架构：$ARCH"
        exit 1
        ;;
esac

echo "TraffMonetizer 镜像：$TM_IMAGE"

# -------------------------
# 安装 Docker
# -------------------------

install_docker() {
    echo "正在安装 Docker..."

    apt-get update

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker.io \
        ca-certificates \
        curl

    systemctl enable docker
    systemctl start docker

    echo "Docker 安装完成"
}

if ! command -v docker >/dev/null 2>&1; then
    install_docker
else
    echo "Docker 已安装，跳过安装"
    systemctl enable docker
    systemctl start docker
fi

if ! docker info >/dev/null 2>&1; then
    echo "Docker 服务不可用"
    exit 1
fi

# -------------------------
# 创建容器函数
# 已存在则删除重建
# -------------------------

create_container() {
    local container_name="$1"
    shift

    if docker container inspect "$container_name" >/dev/null 2>&1; then
        echo "发现已有容器：$container_name"
        echo "停止并删除容器：$container_name"

        docker rm -f "$container_name" >/dev/null
    fi

    echo "创建容器：$container_name"
    docker run -d "$@" >/dev/null

    echo "容器创建完成：$container_name"
}

# -------------------------
# 检查并拉取镜像
# 仅本地不存在时才拉取
# -------------------------

pull_if_missing() {
    local image="$1"

    if docker image inspect "$image" >/dev/null 2>&1; then
        echo "镜像已存在，跳过拉取：$image"
    else
        echo "本地不存在镜像，开始拉取：$image"
        docker pull "$image"
    fi
}

echo "检查 Docker 镜像..."

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
    echo "Watchtower 已存在，重新创建以确保配置正确"

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
# 完成
# -------------------------

echo
echo "=========================================="
echo "tm挂机完成"
echo "=========================================="
echo
echo "容器状态："
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
echo
echo "Watchtower：每 24 小时检查镜像更新"
