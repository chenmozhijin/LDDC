# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
__version__ = "v0.0.1"
import os
import sys
import re
import time
import json
import logging

import requests
from bs4 import BeautifulSoup as bs
from PySide6.QtCore import QObject, Signal, QThread, Slot
from PySide6.QtWidgets import QApplication, QMainWindow, QFileDialog, QMessageBox, QTableWidgetItem, QPushButton

from main_ui import Ui_MainWindow
from decryptor import QRCDecrypt


def escape_filename(filename):
    replacement_dict = {
        '/': '／',
        '\\': '＼',
        ':': '：',
        '*': '＊',
        '?': '？',
        '"': '＂',
        '<': '＜',
        '>': '＞',
        '|': '｜'
    }

    for char, replacement in replacement_dict.items():
        filename = filename.replace(char, replacement)

    return filename


class Search(QObject):
    error = Signal(str)
    result = Signal(list)
    finished = Signal()

    def __init__(self):
        super().__init__()

        self.cache = {}

    def search_music(self, name, limit=20):
        if (name, limit) in self.cache:
            self.result.emit(self.cache[(name, limit)])
            self.finished.emit()
        url = 'https://shc.y.qq.com/soso/fcgi-bin/search_for_qq_cp'
        headers = {
            'Accept': '*/*',
            'Accept-Encoding': 'gzip, deflate, br',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
            'Referer': 'https://y.qq.com/',
            'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 13_3_1 like Mac OS X; zh-CN) AppleWebKit/537.51.1 ('
                          'KHTML, like Gecko) Mobile/17D50 UCBrowser/12.8.2.1268 Mobile AliApp(TUnionSDK/0.1.20.3) '
        }
        params = {
            '_': '1657641526460',
            'g_tk': '1037878909',
            'uin': '1804681355',
            'format': 'json',
            'inCharset': 'utf-8',
            'outCharset': 'utf-8',
            'notice': '0',
            'platform': 'h5',
            'needNewCode': '1',
            'w': name,
            'zhidaqu': '1',
            'catZhida': '1',
            't': '0',
            'flag': '1',
            'ie': 'utf-8',
            'sem': '1',
            'aggr': '0',
            'perpage': str(limit),
            'n': str(limit),
            'p': '1',
            'remoteplace': 'txt.mqq.all'
        }

        try:
            response = requests.get(url, headers=headers, params=params)
            response.raise_for_status()  # 引发 HTTP 错误异常
            orig_lyric_infos = response.json()['data']['song']['list']
        except requests.exceptions.RequestException as e:
            logging.error(f"搜索请求错误: {e}")
            self.error.emit(f"搜索请求错误{e}")
            self.finished.emit()
            return
        except (KeyError, IndexError, json.JSONDecodeError) as e:
            logging.error(f"搜索结果解析错误: {e}")
            self.error.emit(f"搜索结果解析错误{e}")
            self.finished.emit()
            return

        if len(orig_lyric_infos) == 0:
            logging.error(f"找不到歌曲: {name}")
            self.error.emit(f"找不到歌曲: {name}")
            self.finished.emit()
            return

        lyric_infos = []
        logging.debug(f"找到{len(orig_lyric_infos)}首歌曲")
        for lyric_info in orig_lyric_infos:
            songer = ""
            for songer_info in lyric_info['singer']:
                if songer != "":
                    songer += ("/" + songer_info['name'])
                else:
                    songer = songer_info['name']
            lyric_infos.append({"name": lyric_info['songname'], "singer": songer, "album": lyric_info['albumname'], "songid": str(lyric_info['songid'])})

        self.cache[(name, limit)] = lyric_infos
        self.result.emit(lyric_infos)
        self.finished.emit()


class LyricProcessing(QObject):
    result = Signal(dict, list, str)
    error = Signal(str)
    finished = Signal()

    def __init__(self):
        super().__init__()
        self.cache = {}

    def get_lyric(self, song_info, lyric_type):
        if song_info['songid'] in self.cache:
            lyrics_dicts = self.cache[song_info['songid']]
            logging.info(f"从缓存中获取歌词：{song_info['songid']}")
            logging.debug(f"缓存中获取的歌词：{lyrics_dicts}")
        else:
            lyrics = self.download(song_info['songid'])
            if lyrics is None:
                return
            if 'orig' not in lyrics:
                logging.error(f"无法获取歌词：{song_info['songid']}")
                self.error.emit("无法获取歌词")
                return
            lyric_text = ""
            lyrics_dicts = {}

            for key, content in lyrics.items():  # content:(歌词, qrc|lrc)
                if content[1] == "qrc":
                    lyrics_dicts[key] = self.qrc2lrc(content[0])
                elif content[1] == "lrc":
                    lyrics_dicts[key] = content[0]

            self.cache[song_info['songid']] = lyrics_dicts
            logging.info(f"获取歌词(未合并)成功：{song_info['songid']}")
            logging.debug(f"获取的歌词(未合并)：{lyrics_dicts}")

        lyric_text = self.merge_lyrics({key: lyrics_dict for key, lyrics_dict in lyrics_dicts.items() if key in lyric_type})
        logging.info(f"合并歌词成功：{song_info['songid']}")
        self.result.emit(song_info, list(lyrics_dicts.keys()), lyric_text)
        self.finished.emit()

    def download(self, songid):
        def determination_type(text):
            if "<?xml " in text[:10] or "<QrcInfos>" in text[:10]:
                return "qrc"
            else:
                return "lrc"

        params = {
            'version': '15',
            'miniversion': '82',
            'lrctype': '4',
            'musicid': songid,
        }
        try:
            response = requests.get('https://c.y.qq.com/qqmusic/fcgi-bin/lyric_download.fcg', params=params)
            response.raise_for_status()
        except requests.exceptions.RequestException as e:
            logging.error(e)
            return None
        logging.debug(f"获取歌词请求成功：{songid}, {response.text.strip()}")
        qrc_xml = re.sub(r"^<!--|-->$", "", response.text.strip())
        qrc_suop = bs(qrc_xml, 'xml')
        lyrics = {}
        for key, value in [('orig', 'content'), ('ts', 'contentts'), ('roma', 'contentroma')]:
            find_result = qrc_suop.find(value)
            if find_result is not None and find_result['timetag'] != "0":
                encrypted_lyric = find_result.get_text()

                cannot_decrypt = ["789C014000BFFF", "789C014800B7FF"]
                for c in cannot_decrypt:
                    if encrypted_lyric.startswith(c):
                        self.error.emit(f"没有获取到可解密的歌词\n(encrypted_lyric starts with {c})")
                        return None

                lyric, error = self.decrypt(encrypted_lyric)

                if lyric is not None:
                    type_ = determination_type(lyric)
                    if type_ == "qrc":
                        lyric = re.findall(r'<Lyric_1 LyricType="1" LyricContent="(.*?)"/>', lyric, re.DOTALL)[0]
                    lyrics[key] = (lyric, type_)
                elif error is not None:
                    self.error.emit("解密歌词失败, 错误: " + error)
                    return None
            elif find_result['timetag'] == "0" and key == "orig":
                self.error.emit("没有获取到可解密的歌词(timetag=0)")
                return None

        return lyrics

    def decrypt(self, encrypted_data: str):
        if encrypted_data is None or encrypted_data.strip() == "":
            logging.error("没有可解密的数据")
            return None, None
        try:
            return QRCDecrypt(encrypted_data), None
        except Exception as e:
            logging.error(f"解密歌词失败, 错误: {e}")
            return None, str(e)

    def ms2formattime(self, ms: int):
        m, ms = divmod(ms, 60000)
        s, ms = divmod(ms, 1000)
        return "{:02d}:{:02d}.{:03d}".format(int(m), int(s), int(ms))

    def qrc2lrc(self, qrc: str):
        qrc_lines = qrc.split('\n')
        lrc_lines = []
        wrods_split_pattern = re.compile(r'(?:\[\d+,\d+\])?((?:(?!\(\d+,\d+\)).)+)\((\d+),(\d+)\)')  # 逐字匹配
        lines_split_pattern = re.compile(r'\[(\d+),(\d+)\](.*)$')  # 逐行匹配

        for line in qrc_lines:
            line = line.strip()
            lines_split_content = re.findall(lines_split_pattern, line)
            if lines_split_content:  # 判断是否为歌词行
                line_start_time, line_duration, line_content = lines_split_content[0]
                wrods_split_content = re.findall(wrods_split_pattern, line)
                if wrods_split_content:  # 判断是否为逐字歌词
                    lrc_line, last_time = "", None
                    for text, starttime, duration in wrods_split_content:
                        if text != "\r":
                            if int(starttime) != last_time:  # 判断开始时间是否等于上一个结束时间
                                lrc_line += f"[{self.ms2formattime(int(starttime))}]{text}[{self.ms2formattime(int(starttime) + int(duration))}]"
                            else:
                                lrc_line += f"{text}[{self.ms2formattime(int(starttime) + int(duration))}]"
                            last_time = int(starttime) + int(duration)  # 结束时间
                else:  # 如果不是逐字歌词
                    lrc_line = f"[{self.ms2formattime(int(line_start_time))}]{line_content}[{self.ms2formattime(int(line_start_time) + int(line_duration))}]"
                lrc_lines.append(lrc_line)
            else:
                lrc_lines.append(line)
                continue
        return '\n'.join(lrc_lines)

    def time2ms(self, m: int, s: int, ms: int):
        """时间转毫秒"""
        return int((m * 60 + s) * 1000 + ms)

    def find_closest_match(self, list1: list, list2: list):
        list1 = list1[:]
        list2 = list2[:]
        # 存储合并结果的列表
        merged_dict = {}

        # 遍历第一个列表中的每个时间戳和歌词
        i = 0
        while len(list1) > i:
            timestamp1, lyrics1 = list1[i]
            # 找到在第二个列表中最接近的匹配项
            closest_timestamp2, closest_lyrics2 = min(list2, key=lambda x: abs(x[0] - timestamp1))

            if (closest_timestamp2, closest_lyrics2) not in merged_dict:
                merged_dict.update({(closest_timestamp2, closest_lyrics2): (timestamp1, lyrics1)})
            elif abs(timestamp1 - closest_timestamp2) < abs(merged_dict[(closest_timestamp2, closest_lyrics2)][0] - closest_timestamp2):
                list1.append(merged_dict[(closest_timestamp2, closest_lyrics2)])
                merged_dict[(closest_timestamp2, closest_lyrics2)] = (timestamp1, lyrics1)
            else:
                available_items = [(item[0], item[1]) for item in list2 if item not in merged_dict]
                if available_items:
                    closest_timestamp2, closest_lyrics2 = min(available_items, key=lambda x: abs(x[0] - timestamp1))
                    merged_dict[(closest_timestamp2, closest_lyrics2)] = (timestamp1, lyrics1)
                else:
                    logging.warning(f"{timestamp1, lyrics1}无法匹配")

            i += 1

        sorted_items = sorted(((value[0], value[1], key[0], key[1]) for key, value in merged_dict.items()), key=lambda x: x[0])

        return_dict = {(item[0], item[1]): (item[2], item[3]) for item in sorted_items}
        return return_dict

    def islinecontent(self, line):
        content = re.sub(r"\[\d+:\d+\.\d+\]|\[\d+,\d+\]", "", line).strip()
        if content == "" or content == "//":
            return False
        return True

    def merge_lyrics(self, lyrics: dict):
        """合并歌词"""
        logging.debug(f"lyrics:{lyrics}")
        lyric_tagkeys = []
        lyric_times = {}  # key 包含 'orig' 'ts' 'roma'
        lyric_lines = []
        time_text_split_pattern = re.compile(r'^\[(\d+):(\d+)\.(\d+)\](.*)$')
        tag_split_pattern = re.compile(r"^\[([A-Za-z]+):(.*)\]\r?$")
        for key, lyric in lyrics.items():
            lyric_times[key] = []
            for line in lyric.split('\n'):
                if line.startswith('['):
                    lyric_line = time_text_split_pattern.match(line)
                    if lyric_line:  # 歌词行
                        m, s, ms, text = lyric_line.groups()
                        time_ = self.time2ms(int(m), int(s), int(ms))
                        lyric_times[key].append((time_, text))
                        continue
                    tag = tag_split_pattern.match(line)
                    if tag:  # 标签行
                        if tag.groups()[0] not in lyric_tagkeys:
                            lyric_tagkeys.append(tag.groups()[0])
                            lyric_lines.append(line)
                        continue
                    logging.error(f"未知类型的行: {line}")

        if "ts" in lyric_times:
            ts = self.find_closest_match(lyric_times["orig"], lyric_times["ts"])
        if "roma" in lyric_times:
            roma = self.find_closest_match(lyric_times["orig"], lyric_times["roma"])

        end_time_pattern = re.compile(r"(\[\d+:\d+\.\d+\])$")
        for orig_time, orig_line in lyric_times["orig"]:
            orig_start_formattime = f"[{self.ms2formattime(orig_time)}]"
            end_time_matched = re.findall(end_time_pattern, orig_line)
            if end_time_matched:
                orig_end_formattime = end_time_matched[0]
            else:
                orig_end_formattime = ""
            line = orig_start_formattime + orig_line
            if "ts" in lyric_times and (orig_time, orig_line) in ts:
                ts_line = ts[(orig_time, orig_line)][1]
                if self.islinecontent(ts_line):  # 检查是否有实际内容
                    end_time_matched = re.findall(end_time_pattern, ts_line)
                    if end_time_matched:
                        line += f"\n{orig_start_formattime}{ts_line}"
                    else:
                        line += f"\n{orig_start_formattime}{ts_line}{orig_end_formattime}"
            if "roma" in lyric_times and (orig_time, orig_line) in roma:
                roma_line = roma[(orig_time, orig_line)][1]
                if self.islinecontent(roma_line):  # 检查是否有实际内容
                    line = f"{orig_start_formattime}{roma_line}\n" + line
            lyric_lines.append(line)
        return "\n".join(lyric_lines)


class MainWindow(QMainWindow, Ui_MainWindow):
    lyricprocessing_get_lyric = Signal(dict, list)
    search_music = Signal(str, int)

    def __init__(self, parent=None):
        super(MainWindow, self).__init__(parent)
        self.setupUi(self)
        self.program_info_label.setText(f"© {time.strftime('%Y')} 沉默の金 版本：{__version__}")
        self.Connect_signals_and_slot_functions()

        self.LyricProcessing = LyricProcessing()
        self.LyricProcessingthread = QThread()
        self.LyricProcessing.moveToThread(self.LyricProcessingthread)
        self.LyricProcessing.result.connect(self.update_lyric_preview)
        self.LyricProcessing.error.connect(self.LyricProcessingError)
        self.lyricprocessing_get_lyric.connect(self.LyricProcessing.get_lyric)
        self.LyricProcessing.finished.connect(self.LyricProcessingthread.quit)

        self.Search = Search()
        self.Searchthread = QThread()
        self.Search.moveToThread(self.Searchthread)
        self.Search.result.connect(self.update_search_result)
        self.Search.error.connect(self.show_message)
        self.search_music.connect(self.Search.search_music)
        self.Search.finished.connect(self.Searchthread.quit)

        self.lyric_preview_info = None
        self.lyric_info_dict = None
        self.preview_Lyric = {}

        self.path_lineEdit.setText(current_directory + "\\lyrics")

    def Connect_signals_and_slot_functions(self):
        self.Search_pushButton.clicked.connect(self.SearchSong)
        self.Selectpath_pushButton.clicked.connect(self.SelectSavepath)
        self.Translate_checkBox.stateChanged.connect(self.PreviewLyric)
        self.Romanized_checkBox.stateChanged.connect(self.PreviewLyric)
        self.Save_pushButton.clicked.connect(self.SaveLyric)

    @Slot()
    def SearchError(self, error):
        self.Search_pushButton.setEnabled()
        self.Search_pushButton.setText('搜索')
        self.show_message("error", error)
        self.Searchthread.quit()

    @Slot()
    def LyricProcessingError(self, error):
        self.preview_plainTextEdit.setPlainText("")
        self.preview_Lyric = {}
        self.show_message("error", error)
        self.LyricProcessingthread.quit()

    @Slot()
    def SaveLyric(self):
        if self.lyric_info_dict is None or self.lyric_preview_info is None or not self.preview_Lyric:
            return QMessageBox.warning(self, '警告', '请先下载并预览歌词并选择保存路径')
        if self.LyricProcessingthread.isRunning():
            return QMessageBox.warning(self, '警告', '正在处理歌词，请稍等')
        songname = self.preview_Lyric["info"]["name"]
        singer = self.preview_Lyric["info"]["singer"]
        songid = self.preview_Lyric["info"]["songid"]

        save_path = os.path.normpath(self.path_lineEdit.text() + '\\' + escape_filename(singer + ' - ' + songname + f"({songid})" + '.lrc'))
        if os.path.exists(self.path_lineEdit.text()):
            try:
                with open(save_path, 'w', encoding='utf-8') as f:
                    f.write(self.preview_Lyric["lyric"])
                QMessageBox.information(self, '提示', '歌词保存成功')
            except Exception as e:
                QMessageBox.warning(self, '警告', f'歌词保存失败：{e}')
        else:
            QMessageBox.warning(self, '警告', '保存路径不存在')

    @Slot()
    def SelectSavepath(self):
        save_path = QFileDialog.getExistingDirectory(self, "选择保存路径", dir=self.path_lineEdit.text())
        self.path_lineEdit.setText(save_path)

    @Slot()
    def SearchSong(self):
        song_name = self.Songname_lineEdit.text()
        if not song_name:
            QMessageBox.warning(self, "警告", "请输入歌曲名")
            return

        self.Search_pushButton.setDisabled(True)
        self.Search_pushButton.setText('正在搜索...')
        self.Searchresults_tableWidget.setRowCount(0)
        if self.Searchthread.isRunning():
            self.Searchthread.quit()
            self.Searchthread.wait()

        self.Searchthread.start()
        self.search_music.emit(song_name, 20)

    @Slot()
    def update_search_result(self, lyric_infos):
        self.Search_pushButton.setEnabled(True)
        self.Search_pushButton.setText('搜索')
        table = self.Searchresults_tableWidget
        table.setRowCount(0)

        index = 0
        self.lyric_info_dict = {}
        for lyric_info in lyric_infos:
            table.insertRow(table.rowCount())
            table.setItem(table.rowCount() - 1, 1, QTableWidgetItem(lyric_info["name"]))
            table.setItem(table.rowCount() - 1, 2, QTableWidgetItem(lyric_info["singer"]))
            table.setItem(table.rowCount() - 1, 3, QTableWidgetItem(lyric_info["album"]))
            table.setItem(table.rowCount() - 1, 4, QTableWidgetItem(str(lyric_info["songid"])))

            # 添加预览按钮
            preview_button = QPushButton("下载&&预览")
            ObjectName = "PreviewButton" + str(index)
            preview_button.setObjectName(ObjectName)
            table.setCellWidget(table.rowCount() - 1, 0, preview_button)
            index += 1
            self.lyric_info_dict.update({ObjectName: lyric_info})

            # 使用默认参数来捕获循环变量的当前值
            preview_button.clicked.connect(self.PreviewLyric)

        table.resizeColumnsToContents()

    @Slot()
    def show_message(self, type_, message):
        if type_ == "error":
            QMessageBox.critical(self, "错误", message)
        return

    @Slot()
    def update_lyric_preview(self, song_info, lyric_types, lyric_text):
        lyric_info_label_text = "歌词信息："
        if 'ts' in lyric_types:
            lyric_info_label_text += "翻译:有"
        else:
            lyric_info_label_text += "翻译:无"
        if 'roma' in lyric_types:
            lyric_info_label_text += " 罗马音:有"
        else:
            lyric_info_label_text += " 罗马音:无"
        self.lyric_info_label.setText(lyric_info_label_text)
        self.preview_plainTextEdit.setPlainText(lyric_text)
        self.preview_Lyric = {"info": song_info, "lyric": lyric_text}

    @Slot()
    def PreviewLyric(self):
        sender_button = self.sender()  # 获取发送信号的按钮
        if self.lyric_info_dict and sender_button.objectName() in self.lyric_info_dict:  # 如果信号来自搜索结果的按钮
            lyric_info_dict = self.lyric_info_dict[sender_button.objectName()]  # 获取对应的信息
        elif self.lyric_preview_info:  # 如果信号来自 译文/罗马音 的选择框且已经 下载&预览 过歌词
            lyric_info_dict = self.lyric_preview_info
        else:
            return
        self.lyric_preview_info = lyric_info_dict

        self.lyric_info_label.setText("歌词信息：无")
        self.preview_plainTextEdit.setPlainText("处理中...")
        self.preview_Lyric = {}

        lyric_type = ['orig']
        if self.Translate_checkBox.isChecked():
            lyric_type.append('ts')
        if self.Romanized_checkBox.isChecked():
            lyric_type.append("roma")

        if self.LyricProcessingthread.isRunning():
            self.LyricProcessingthread.quit()
            self.LyricProcessingthread.wait()

        self.LyricProcessingthread.start()
        self.lyricprocessing_get_lyric.emit(lyric_info_dict, lyric_type)


if __name__ == "__main__":
    current_directory = os.path.dirname(os.path.abspath(__file__))

    if not os.path.exists("log"):
        os.mkdir("log")
    if not os.path.exists("lyrics"):
        os.mkdir("lyrics")

    logging.basicConfig(filename=f'log\\{time.strftime("%Y.%m.%d",time.localtime())}.log', encoding='utf-8', format='[%(levelname)s]%(asctime)s - %(module)s(%(lineno)d) - %(funcName)s:%(message)s', level=logging.DEBUG)

    app = QApplication(sys.argv)

    mainWindow = MainWindow()
    mainWindow.show()
    sys.exit(app.exec())
