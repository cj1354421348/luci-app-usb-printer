#!/usr/bin/env python3
"""
po2lmo.py — 将 OpenWrt LuCI .po 翻译文件编译为 .lmo 二进制格式

LMO 文件格式（大端序）：
  [条目区] N × 16 字节，每条：
      key_id  : uint32  msgid 的 FNV-1a 哈希
      val_id  : uint32  msgstr 的 FNV-1a 哈希
      offset  : uint32  msgstr 在字符串数据区的起始偏移
      length  : uint32  msgstr 的字节长度
  [字符串数据区] 所有 msgstr 依次拼接（无分隔符）
  [文件末尾]   uint32  条目总数

条目按 key_id 升序排列，供二分查找。
"""

import sys
import re
import struct

# ── FNV-1a 32-bit ──────────────────────────────────────────────
FNV_PRIME  = 0x01000193
FNV_OFFSET = 0x811c9dc5

def fnv1a32(text: str) -> int:
    h = FNV_OFFSET
    for byte in text.encode('utf-8'):
        h ^= byte
        h = (h * FNV_PRIME) & 0xFFFFFFFF
    return h

# ── .po 解析 ───────────────────────────────────────────────────
def unescape(s: str) -> str:
    """处理 .po 字符串中的 \\n \\t \\\\ 等转义"""
    return s.replace('\\n', '\n') \
            .replace('\\t', '\t') \
            .replace('\\"', '"')  \
            .replace('\\\\', '\\')

def parse_po(filename: str):
    """返回 [(msgid, msgstr), ...] 列表，跳过空 msgid（头部）和空 msgstr"""
    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()

    entries = []
    # 匹配 msgid + msgstr 块（支持多行拼接格式）
    block_re = re.compile(
        r'msgid\s+((?:"[^"]*"\s*)+?)\s*\n'
        r'msgstr\s+((?:"[^"]*"\s*)+)',
        re.MULTILINE
    )
    str_re = re.compile(r'"([^"]*)"')

    for match in block_re.finditer(content):
        msgid  = unescape(''.join(str_re.findall(match.group(1))))
        msgstr = unescape(''.join(str_re.findall(match.group(2))))

        if not msgid or not msgstr:   # 跳过头部和未翻译条目
            continue

        entries.append((msgid, msgstr))

    return entries

# ── 生成 .lmo ──────────────────────────────────────────────────
def po2lmo(po_file: str, lmo_file: str):
    entries = parse_po(po_file)

    if not entries:
        print(f"警告：{po_file} 中没有可翻译条目", file=sys.stderr)
        return

    # 构建字符串数据区 & 条目记录
    string_data = b''
    records = []

    for msgid, msgstr in entries:
        msgstr_bytes = msgstr.encode('utf-8')
        records.append((
            fnv1a32(msgid),   # key_id
            fnv1a32(msgstr),  # val_id
            len(string_data), # offset（相对字符串数据区起始）
            len(msgstr_bytes) # length
        ))
        string_data += msgstr_bytes

    # 按 key_id 升序排列（供二分查找）
    records.sort(key=lambda r: r[0])

    with open(lmo_file, 'wb') as f:
        # 写条目区
        for key_id, val_id, offset, length in records:
            f.write(struct.pack('>IIII', key_id, val_id, offset, length))
        # 写字符串数据区
        f.write(string_data)
        # 写末尾条目总数
        f.write(struct.pack('>I', len(records)))

    print(f"生成：{lmo_file}  ({len(records)} 条翻译)")

# ── 入口 ───────────────────────────────────────────────────────
if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"用法：{sys.argv[0]} <输入.po> <输出.lmo>")
        sys.exit(1)
    po2lmo(sys.argv[1], sys.argv[2])
