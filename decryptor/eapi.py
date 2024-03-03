import binascii
import hashlib
import json
from base64 import b64encode
from binascii import a2b_hex

from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad


def eapi_params_encrypt(path: bytes, params: dict) -> str:
    """
    eapi接口参数加密
    :param path: url路径
    :param params: 明文参数
    :return str: 请求data
    """
    params_bytes = json.dumps(params, separators=(',', ':')).encode()
    sign_src = b'nobody' + path + b'use' + params_bytes + b'md5forencrypt'
    sign = hashlib.md5(sign_src).hexdigest()  # noqa: S324
    aes_src = path + b'-36cd479b6b5-' + params_bytes + b'-36cd479b6b5-' + sign.encode()
    aes_src_padded = pad(aes_src, AES.block_size)
    crypt = AES.new(b'e82ckenh8dichen8', AES.MODE_ECB)
    encrypted_data = crypt.encrypt(aes_src_padded)
    return f"params={binascii.hexlify(encrypted_data).upper().decode()}"


def eapi_params_decrypt(encrypted_text: str) -> dict:
    """
    解密使用 _eapi_encrypt 函数加密的文本
    :param crypto_text: 加密文本
    :return: 解密后的 dict 对象
    """
    encrypted_bytes = a2b_hex(encrypted_text)
    crypt = AES.new(b'e82ckenh8dichen8', AES.MODE_ECB)
    decrypted_bytes = crypt.decrypt(encrypted_bytes)
    unpadded_bytes = unpad(decrypted_bytes, AES.block_size)
    decrypted_text = unpadded_bytes.decode()
    parts = decrypted_text.split('-36cd479b6b5-')
    path = parts[0].encode()
    params = parts[1].encode()
    params = json.loads(params)
    sign_src = b'nobody' + path + b'use' + json.dumps(params, separators=(',', ':')).encode() + b'md5forencrypt'
    m = hashlib.md5()  # noqa: S324
    m.update(sign_src)
    return params


def eapi_response_decrypt(cipher_buffer: bytes) -> bytes:
    cipher = AES.new(b'e82ckenh8dichen8', AES.MODE_ECB)
    decrypted = cipher.decrypt(cipher_buffer)
    return unpad(decrypted, AES.block_size)


def get_cache_key(data: str | bytes) -> str:
    if isinstance(data, str):
        data = data.encode()
    cipher = AES.new(b")(13daqP@ssw0rd~", AES.MODE_ECB)
    padded_data = pad(data, AES.block_size)
    encrypted = cipher.encrypt(padded_data)
    return b64encode(encrypted).decode()
