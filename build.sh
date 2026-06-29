#!/bin/bash
# =============================================================
# Build script for luci-app-usb-printer
# 纯 Lua/Shell 包，无 C 代码，架构标记为 all
# 用法：bash build.sh
# =============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PKG_NAME="luci-app-usb-printer"
PKG_VERSION="1.0"
PKG_RELEASE="20230116"
PKG_ARCH="all"
PKG_FULL="${PKG_NAME}_${PKG_VERSION}-${PKG_RELEASE}_${PKG_ARCH}"

SRC="${SCRIPT_DIR}/package/feeds/luci/luci-app-usb-printer"
BUILD="${SCRIPT_DIR}/build/${PKG_FULL}"
OUTPUT="${SCRIPT_DIR}/output"
PO2LMO="${SCRIPT_DIR}/tools/po2lmo.py"

echo "========================================"
echo " Building: ${PKG_FULL}.ipk"
echo "========================================"

# ── 检查依赖 ────────────────────────────────
if ! command -v python3 &>/dev/null; then
    echo "错误：需要 python3（用于编译 .po → .lmo）"
    exit 1
fi
if ! command -v ar &>/dev/null; then
    echo "错误：需要 ar（binutils）"
    exit 1
fi

# ── 清理旧构建 ──────────────────────────────
rm -rf "${BUILD}"
mkdir -p "${BUILD}/control" "${BUILD}/data" "${OUTPUT}"

# ── 1. 安装数据文件 ─────────────────────────
echo "[1/5] 整理 data 文件..."

install -Dm644 "${SRC}/root/etc/config/usb_printer" \
               "${BUILD}/data/etc/config/usb_printer"

install -Dm755 "${SRC}/root/etc/hotplug.d/usb/10-usb_printer" \
               "${BUILD}/data/etc/hotplug.d/usb/10-usb_printer"

install -Dm755 "${SRC}/root/etc/init.d/usb_printer" \
               "${BUILD}/data/etc/init.d/usb_printer"

install -Dm755 "${SRC}/root/etc/uci-defaults/luci-usb-printer" \
               "${BUILD}/data/etc/uci-defaults/luci-usb-printer"

install -Dm755 "${SRC}/root/usr/bin/detectlp" \
               "${BUILD}/data/usr/bin/detectlp"

install -Dm755 "${SRC}/root/usr/bin/usb_printer_hotplug" \
               "${BUILD}/data/usr/bin/usb_printer_hotplug"

install -Dm644 "${SRC}/luasrc/controller/usb_printer.lua" \
               "${BUILD}/data/usr/lib/lua/luci/controller/usb_printer.lua"

install -Dm644 "${SRC}/luasrc/model/cbi/usb_printer.lua" \
               "${BUILD}/data/usr/lib/lua/luci/model/cbi/usb_printer.lua"

# ── 2. 编译 i18n（.po → .lmo）───────────────
echo "[2/5] 编译汉化文件..."

PO_FILE="${SRC}/po/zh-cn/usb-printer.po"
LMO_DIR="${BUILD}/data/usr/lib/lua/luci/i18n"
LMO_FILE="${LMO_DIR}/usb-printer.zh-cn.lmo"

mkdir -p "${LMO_DIR}"
python3 "${PO2LMO}" "${PO_FILE}" "${LMO_FILE}"

# ── 3. 生成 control 文件 ────────────────────
echo "[3/5] 生成 control 文件..."

INSTALLED_SIZE=$(du -sk "${BUILD}/data" | cut -f1)

cat > "${BUILD}/control/control" << EOF
Package: ${PKG_NAME}
Version: ${PKG_VERSION}-${PKG_RELEASE}
Depends: p910nd
Architecture: ${PKG_ARCH}
Installed-Size: ${INSTALLED_SIZE}
Description: USB Printer Share via TCP/IP
 Shares multiple USB printers via TCP/IP using p910nd.
 Automatically binds printers by VID/PID, independent of /dev/usb/lp device order.
EOF

# postinst：安装后自动 enable 开机启动
cat > "${BUILD}/control/postinst" << 'EOF'
#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -x /etc/init.d/usb_printer ] && /etc/init.d/usb_printer enable
exit 0
EOF
chmod 755 "${BUILD}/control/postinst"

# prerm：卸载前自动 disable
cat > "${BUILD}/control/prerm" << 'EOF'
#!/bin/sh
[ -x /etc/init.d/usb_printer ] && /etc/init.d/usb_printer disable
exit 0
EOF
chmod 755 "${BUILD}/control/prerm"

# ── 4. 打 tar 包 ────────────────────────────
echo "[4/5] 打 tar 包..."

echo "2.0" > "${BUILD}/debian-binary"

tar -czf "${BUILD}/control.tar.gz" -C "${BUILD}/control" .
tar -czf "${BUILD}/data.tar.gz"    -C "${BUILD}/data"    .

# ── 5. 打 IPK ──────────────────────────────
echo "[5/5] 生成 IPK..."

ar r "${OUTPUT}/${PKG_FULL}.ipk" \
    "${BUILD}/debian-binary"   \
    "${BUILD}/control.tar.gz"  \
    "${BUILD}/data.tar.gz"

# ── 完成 ────────────────────────────────────
echo ""
echo "========================================"
echo " 完成！"
echo " 输出：${OUTPUT}/${PKG_FULL}.ipk"
echo " 大小：$(du -sh "${OUTPUT}/${PKG_FULL}.ipk" | cut -f1)"
echo "========================================"
