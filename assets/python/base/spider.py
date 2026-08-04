import json
import warnings
from abc import ABCMeta, abstractmethod
import requests
from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad

warnings.filterwarnings("ignore")
requests.packages.urllib3.disable_warnings()

class Spider(metaclass=ABCMeta):
    def __init__(self, extend=""):
        self.extend = extend
        self.session = requests.Session()

    @abstractmethod
    def init(self, extend=""): pass

    @abstractmethod
    def homeContent(self, filter): pass

    @abstractmethod
    def categoryContent(self, tid, pg, filter, extend): pass

    @abstractmethod
    def detailContent(self, ids): pass

    @abstractmethod
    def searchContent(self, key, quick, pg=1): pass

    @abstractmethod
    def playerContent(self, flag, id, vipFlags): pass

    def fetch(self, url, headers=None, timeout=10):
        r = self.session.get(url, headers=headers, timeout=timeout, verify=False)
        r.encoding = 'utf-8'
        return r.text

    @staticmethod
    def aes_cbc_decode(ciphertext, key, iv):
        import base64
        ct = base64.b64decode(ciphertext)
        cipher = AES.new(key.encode(), AES.MODE_CBC, iv.encode())
        return unpad(cipher.decrypt(ct), AES.block_size).decode()