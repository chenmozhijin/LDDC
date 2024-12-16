# LDDC

[中文](./README.md) | [English](./README_en.md) | 日本語

> 高精度な歌詞（逐字歌詞）のダウンロード、復号、変換ツール

[![Codacy Badge](https://app.codacy.com/project/badge/Grade/015f636391584ffc82790ff7038da5ca)](https://app.codacy.com/gh/chenmozhijin/LDDC/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)  
[![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/chenmozhijin/LDDC/total)](https://github.com/chenmozhijin/LDDC/releases/latest)  
[![Static Badge](https://img.shields.io/badge/Python-3.10%2B-brightgreen)](https://www.python.org/downloads/)  
[![Static Badge](https://img.shields.io/badge/License-GPLv3-blue)](https://github.com/chenmozhijin/LDDC/blob/main/LICENSE)  
[![release](https://img.shields.io/github/v/release/chenmozhijin/LDDC?color=blue)](https://github.com/chenmozhijin/LDDC/releases/latest)

## 機能

- [x] QQ音楽、酷狗音楽、NetEase Cloud Musicの楽曲、アルバム、プレイリストを検索可能
- [x] 楽曲を検索画面にドラッグ＆ドロップして自動的に歌詞を検索・マッチング
- [x] ローカル楽曲ファイルにワンクリックで歌詞をマッチング
- [x] アルバムやプレイリスト全体の歌詞をワンクリックでダウンロード
- [x] 多様な形式で保存可能（逐字lrc、逐行lrc、拡張型lrc、srt、ass）
- [x] ダブルクリックで歌詞をプレビューし、即保存
- [x] 原文、翻訳、ローマ字の組み合わせ自由
- [x] 保存パスに多様なプレースホルダーを利用可能
- [x] 暗号化されたローカル歌詞ファイルを開くことに対応
- [x] マルチプラットフォーム対応
- [x] デスクトップ歌詞（現在foobar2000のみ対応: [foo_lddc](https://github.com/chenmozhijin/foo_lddc)）
    1. マルチスレッドによる高速検索で歌詞を自動マッチング（ほとんどが逐字形式）
    2. カラオケ形式の歌詞表示に対応
    3. 原文、翻訳、ローマ字の行分け表示に対応
    4. フェードイン・フェードアウトエフェクトと画面リフレッシュレートの同期で滑らかな表示を実現
    5. 検索画面に似たウィンドウで手動で歌詞を選択可能
    6. 文字キャッシュの実装でリソース使用量を低減
    7. カスタマイズ可能な文字のグラデーションカラー対応

## プレビュー

### 楽曲をドラッグして歌詞を迅速にマッチング

![gif](img/drop.gif)

### 検索画面

![image](img/ja_1.jpg)

### ローカルファイルのマッチング

![image](img/ja_3.jpg)

### 歌詞を開く/設定画面

![image](img/ja_2.jpg)

### デスクトップ歌詞

![image](img/zh-Hans_4.jpg)
![gif](img/desktop_lyrics.gif)

## 使用方法

詳細は[LDDC使用ガイド](https://github.com/chenmozhijin/LDDC/wiki)を参照してください。

## 感謝

一部の機能は以下のプロジェクトを参考にしています:

### 歌詞の復号

[![Readme Card](https://github-readme-stats.vercel.app/api/pin/?username=WXRIW&repo=QQMusicDecoder)](https://github.com/WXRIW/QQMusicDecoder)  
[![Readme Card](https://github-readme-stats.vercel.app/api/pin/?username=jixunmoe&repo=qmc-decode)](https://github.com/jixunmoe/qmc-decode)

### 音楽プラットフォームAPI

[![Readme Card](https://github-readme-stats.vercel.app/api/pin/?username=MCQTSS&repo=MCQTSS_QQMusic)](https://github.com/MCQTSS/MCQTSS_QQMusic)
