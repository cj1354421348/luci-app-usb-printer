#!/bin/bash
# =============================================================
# Build script for luci-app-usb-printer
# 使用 OpenWrt 24.10 官方 SDK 正规编译
# Target: iStoreOS 24.10 / rockchip/armv8 / aarch64_generic
# 用法：bash build.sh
# =============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PKG_NAME="luci-app-usb-printer"
PKG_SRC="${SCRIPT_DIR}/package/feeds/luci/luci-app-usb-printer"
OUTPUT="${SCRIPT_DIR}/output"

# iStoreOS 24.10 对应 OpenWrt 24.10 / rockchip/armv8
SDK_VER="24.10.0"
SDK_TARGET="rockchip/armv8"
SDK_URL_BASE="https://downloads.openwrt.org/releases/${SDK_VER}/targets/${SDK_TARGET}"
SDK_DIR="${SCRIPT_DIR}/openwrt-sdk"

mkdir -p "${OUTPUT}"

echo "========================================"
echo " luci-app-usb-printer SDK 编译脚本"
echo " Target : iStoreOS 24.10 / rockchip/armv8"
echo " SDK Dir: ${SDK_DIR}"
echo "========================================"

# ── 1. 下载并解压 SDK（有缓存则跳过）──────────
if [ ! -d "${SDK_DIR}" ]; then
    echo ""
    echo "[1/4] 下载 OpenWrt ${SDK_VER} SDK（首次运行约需 5~10 分钟）..."

    # 自动从 index 页面查找正确的 SDK 文件名
    SDK_FILE=$(wget -q -O- "${SDK_URL_BASE}/" \
        | grep -o 'openwrt-sdk-[^"]*Linux-x86_64\.tar\.xz' \
        | head -1)

    if [ -z "${SDK_FILE}" ]; then
        echo "错误：无法自动获取 SDK 文件名，请手动访问："
        echo "  ${SDK_URL_BASE}/"
        echo "找到 openwrt-sdk-*.Linux-x86_64.tar.xz 文件名后，"
        echo "手动执行：wget ${SDK_URL_BASE}/<文件名>"
        exit 1
    fi

    echo "  找到：${SDK_FILE}"
    TARBALL="${SCRIPT_DIR}/${SDK_FILE}"

    [ -f "${TARBALL}" ] || wget -c "${SDK_URL_BASE}/${SDK_FILE}" -O "${TARBALL}"

    echo "  解压中（xz 解压较慢，请耐心等待）..."
    tar -xJf "${TARBALL}" -C "${SCRIPT_DIR}"

    # 找到解压出的目录并改名
    EXTRACTED=$(find "${SCRIPT_DIR}" -maxdepth 1 -name "openwrt-sdk-*" -type d | head -1)
    if [ -z "${EXTRACTED}" ]; then
        echo "错误：未找到解压出的 SDK 目录"
        exit 1
    fi
    mv "${EXTRACTED}" "${SDK_DIR}"

    echo ""
    echo "  初始化 feeds（含 luci feed，约需 3~5 分钟）..."
    cd "${SDK_DIR}"
    ./scripts/feeds update -a
    ./scripts/feeds install -a

    echo "  SDK 初始化完成，下次运行将直接复用"
else
    echo ""
    echo "[1/4] SDK 已存在，直接复用：${SDK_DIR}"
fi

# ── 2. 注入我们的包源码 ────────────────────────
echo ""
echo "[2/4] 注入包源码..."
cd "${SDK_DIR}"

# 放入 feeds/luci/ 目录（包 Makefile 的 include ../../luci.mk 从这里解析）
rm -rf "feeds/luci/${PKG_NAME}"
cp -r "${PKG_SRC}" "feeds/luci/${PKG_NAME}"

# 在 package/feeds/luci/ 下创建符号链接（让 OpenWrt 构建系统能找到该包）
mkdir -p "package/feeds/luci"
rm -f "package/feeds/luci/${PKG_NAME}"
ln -sf "$(realpath "feeds/luci/${PKG_NAME}")" \
       "package/feeds/luci/${PKG_NAME}"

echo "  符号链接：package/feeds/luci/${PKG_NAME}"
echo "         → feeds/luci/${PKG_NAME}"

# ── 3. 编译 ────────────────────────────────────
echo ""
echo "[3/4] 开始编译..."
make "package/feeds/luci/${PKG_NAME}/compile" V=99

# ── 4. 收集输出 IPK ────────────────────────────
echo ""
echo "[4/4] 收集输出..."
IPK=$(find bin/ -name "${PKG_NAME}*.ipk" 2>/dev/null | sort | tail -1)

if [ -z "${IPK}" ]; then
    echo "错误：未找到输出 IPK，请检查上方编译日志"
    exit 1
fi

cp "${IPK}" "${OUTPUT}/"
RESULT="${OUTPUT}/$(basename "${IPK}")"

echo ""
echo "========================================"
echo " 完成！"
echo " 输出：${RESULT}"
echo " 大小：$(du -sh "${RESULT}" | cut -f1)"
echo "========================================"
