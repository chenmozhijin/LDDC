# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from zlib import decompress

from LDDC.common.exceptions import LyricsDecryptError
from LDDC.common.logger import logger
from LDDC.common.models import QrcType
from LDDC.core.decryptor.qmc1 import qmc1_decrypt
from LDDC.core.decryptor.tripledes import DECRYPT, tripledes_crypt, tripledes_key_setup

QRC_KEY = b"!@#)(*$%123ZXC!@!@#)(NHL"
KRC_KEY = b"@Gaw^2tGQ61-\xce\xd2ni"


def qrc_decrypt(encrypted_qrc: str | bytearray | bytes, qrc_type: QrcType = QrcType.CLOUD) -> str:
    if encrypted_qrc is None or encrypted_qrc.strip() == "":
        logger.error("没有可解密的数据")
        msg = "没有可解密的数据"
        raise LyricsDecryptError(msg)

    if isinstance(encrypted_qrc, str):
        encrypted_text_byte = bytearray.fromhex(encrypted_qrc)  # 将文本解析为字节数组
    elif isinstance(encrypted_qrc, bytearray):
        encrypted_text_byte = encrypted_qrc
    elif isinstance(encrypted_qrc, bytes):
        encrypted_text_byte = bytearray(encrypted_qrc)
    else:
        logger.error("无效的加密数据类型")
        msg = "无效的加密数据类型"
        raise LyricsDecryptError(msg)

    try:
        if qrc_type == QrcType.LOCAL:
            qmc1_decrypt(encrypted_text_byte)
            encrypted_text_byte = encrypted_text_byte[11:]

        data = bytearray()
        schedule = tripledes_key_setup(QRC_KEY, DECRYPT)

        # 以 8 字节为单位迭代 encrypted_text_byte
        for i in range(0, len(encrypted_text_byte), 8):
            data += tripledes_crypt(encrypted_text_byte[i:], schedule)

        decrypted_qrc = decompress(data).decode("utf-8")
    except Exception as e:
        logger.exception("QRC解密失败")
        msg = "QRC解密失败"
        raise LyricsDecryptError(msg) from e
    return decrypted_qrc


def krc_decrypt(encrypted_lyrics: bytearray | bytes) -> str:
    if isinstance(encrypted_lyrics, bytes):
        encrypted_data = bytearray(encrypted_lyrics)[4:]
    elif isinstance(encrypted_lyrics, bytearray):
        encrypted_data = encrypted_lyrics[4:]
    else:
        logger.error("无效的加密数据类型")
        msg = "无效的加密数据类型"
        raise LyricsDecryptError(msg)

    try:
        decrypted_data = bytearray()
        for i, item in enumerate(encrypted_data):
            decrypted_data.append(item ^ KRC_KEY[i % len(KRC_KEY)])

        return decompress(decrypted_data).decode('utf-8')
    except Exception as e:
        logger.exception("KRC解密失败")
        msg = "KRC解密失败"
        raise LyricsDecryptError(msg) from e
