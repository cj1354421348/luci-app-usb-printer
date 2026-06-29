#!/usr/bin/env python3
"""
mkipk.py — 直接按字节生成 OpenWrt opkg 兼容的 .ipk 文件
绕开 GNU ar 的扩展头（符号表/长文件名），只输出最纯净的 ar 格式。

用法：python3 mkipk.py <输出.ipk> <debian-binary> <control.tar.xz> <data.tar.xz>

ar 文件格式（每个成员）：
  全局魔数  "!<arch>\n"  8 字节
  ──成员头（共 60 字节）──
  文件名    16 字节  右填充空格，末尾加 '/'
  修改时间  12 字节  十进制字符串，右填充空格
  UID       6 字节   十进制
  GID       6 字节   十进制
  权限      8 字节   八进制
  文件大小  10 字节  十进制
  魔数      2 字节   '`\n'
  ──数据──
  原始文件内容，若长度为奇数则补一字节 '\n'
"""

import sys
import os

AR_MAGIC = b"!<arch>\n"
AR_FMAG  = b"`\n"

def make_member(name: str, data: bytes) -> bytes:
    size = len(data)

    # 成员头：严格按 ar 标准格式，每字段右填充空格
    name_field  = (name + "/").ljust(16).encode("ascii")
    mtime_field = b"0".ljust(12)
    uid_field   = b"0".ljust(6)
    gid_field   = b"0".ljust(6)
    mode_field  = b"100644".ljust(8)
    size_field  = str(size).encode("ascii").ljust(10)

    header = (name_field + mtime_field + uid_field +
              gid_field + mode_field + size_field + AR_FMAG)
    assert len(header) == 60, f"ar header length error: {len(header)}"

    # 数据必须对齐到偶数字节边界
    padding = b"\n" if size % 2 else b""
    return header + data + padding

def create_ipk(output_path: str, debian_binary: str,
               control_gz: str, data_gz: str):
    def read(path):
        with open(path, "rb") as f:
            return f.read()

    members = [
        ("debian-binary",  read(debian_binary)),
        ("control.tar.gz", read(control_gz)),
        ("data.tar.gz",    read(data_gz)),
    ]

    with open(output_path, "wb") as f:
        f.write(AR_MAGIC)
        for name, data in members:
            f.write(make_member(name, data))

    size = os.path.getsize(output_path)
    print(f"生成：{output_path}  ({size} bytes)")

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print(f"用法：{sys.argv[0]} <输出.ipk> <debian-binary> "
              f"<control.tar.gz> <data.tar.gz>")
        sys.exit(1)
    create_ipk(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
