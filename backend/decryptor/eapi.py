# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

import binascii
import hashlib
import json
from base64 import b64decode, b64encode

from pyaes import AESModeOfOperationECB


def pkcs7_pad(data: bytes, block_size: int = 16) -> bytes:
    pad_len = block_size - (len(data) % block_size)
    padding = bytes([pad_len] * pad_len)
    return data + padding


def pkcs7_unpad(data: bytes) -> bytes:
    pad_len = data[-1]
    if pad_len < 1 or pad_len > 16:
        msg = "Invalid padding encountered."
        raise ValueError(msg)
    return data[:-pad_len]


def aes_encrypt(data: str | bytes, key: bytes) -> bytes:
    if isinstance(data, str):
        data = data.encode()
    padded_data = pkcs7_pad(data)  # Ensure the data is padded
    aes = AESModeOfOperationECB(key)  # Using ECB mode
    encrypted_data = b''
    for i in range(0, len(padded_data), 16):
        encrypted_data += aes.encrypt(padded_data[i:i + 16])  # Encrypt in 16-byte blocks
    return encrypted_data


def aes_decrypt(cipher_buffer: bytes, key: bytes) -> bytes:
    aes = AESModeOfOperationECB(key)  # Using ECB mode
    decrypted_data = b''
    for i in range(0, len(cipher_buffer), 16):
        decrypted_data += aes.decrypt(cipher_buffer[i:i + 16])  # Decrypt in 16-byte blocks
    return pkcs7_unpad(decrypted_data)  # Remove padding after decryption


def eapi_params_encrypt(path: bytes, params: dict) -> str:
    """eapi接口参数加密.

    :param path: url路径
    :param params: 明文参数
    :return str: 请求data.
    """
    params_bytes = json.dumps(params, separators=(',', ':')).encode()
    sign_src = b'nobody' + path + b'use' + params_bytes + b'md5forencrypt'
    sign = hashlib.md5(sign_src).hexdigest()  # noqa: S324
    aes_src = path + b'-36cd479b6b5-' + params_bytes + b'-36cd479b6b5-' + sign.encode()
    encrypted_data = aes_encrypt(aes_src, b'e82ckenh8dichen8')
    return f"params={binascii.hexlify(encrypted_data).upper().decode()}"


def eapi_params_decrypt(encrypted_text: str) -> dict:
    """解密使用 _eapi_encrypt 函数加密的文本.

    :param crypto_text: 加密文本
    :return: 解密后的 dict 对象
    """
    encrypted_bytes = binascii.unhexlify(encrypted_text)
    decrypted_data = aes_decrypt(encrypted_bytes, b'e82ckenh8dichen8')
    decrypted_text = decrypted_data.decode()
    parts = decrypted_text.split('-36cd479b6b5-')
    path = parts[0].encode()
    params = json.loads(parts[1])
    sign_src = b'nobody' + path + b'use' + json.dumps(params, separators=(',', ':')).encode() + b'md5forencrypt'
    m = hashlib.md5()  # noqa: S324
    m.update(sign_src)
    return params


def get_cache_key(data: str | bytes) -> str:
    return b64encode(aes_encrypt(data, b")(13daqP@ssw0rd~")).decode()


def cache_key_decrypt(data: str | bytes) -> str:
    return aes_decrypt(b64decode(data), b")(13daqP@ssw0rd~").decode()


def eapi_response_decrypt(cipher_buffer: bytes) -> bytes:
    return aes_decrypt(cipher_buffer, b'e82ckenh8dichen8')
