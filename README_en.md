# LDDC

[中文](./README.md) | English

> Accurate Lyrics (verbatim lyrics) Download, Decryption, and Conversion

[![Codacy Badge](https://app.codacy.com/project/badge/Grade/015f636391584ffc82790ff7038da5ca)](https://app.codacy.com/gh/chenmozhijin/LDDC/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/chenmozhijin/LDDC/total)](https://github.com/chenmozhijin/LDDC/releases/latest)
[![Static Badge](https://img.shields.io/badge/Python-3.10%2B-brightgreen)](https://www.python.org/downloads/)
[![Static Badge](https://img.shields.io/badge/License-GPLv3-blue)](https://github.com/chenmozhijin/LDDC/blob/main/LICENSE)
[![release](https://img.shields.io/github/v/release/chenmozhijin/LDDC?color=blue)](https://github.com/chenmozhijin/LDDC/releases/latest)

## Features

- [x] Search for singles, albums, and playlists on QQ Music, Kugou Music, and NetEase Cloud Music
- [x] One-click download of lyrics for entire albums and playlists
- [x] One-click match lyrics for local song files
- [x] Support for saving in multiple formats (verbatim lrc,line by line lrc,Enhanced LRC, srt, ass)
- [x] Double-click to preview lyrics and save directly
- [x] Merge lyrics of various types (original, translated, romanized) at will
- [x] Save path with various placeholders for arbitrary combinations
- [x] Support for opening locally encrypted lyrics
- [x] Multi-platform support
- [x] Desktop Lyrics (currently only supports foobar2000: [foo_lddc](https://github.com/chenmozhijin/foo_lddc))
    1. Multithreaded fast automatic lyrics matching (mostly word-by-word)
    2. Accurate word-by-word karaoke-style lyrics
    3. Supports displaying the original text, translation, and romanization in separate lines
    4. Supports fade in/out, automatically matches screen refresh rate for smooth display
    5. Supports manually selecting lyrics and adding offsets (similar to the search interface)
    6. Caches characters to achieve low resource usage
    7. Supports custom gradient colors for characters

## Preview

![image](img/en_1.jpg)
![image](img/en_2.jpg)

![gif](img/desktop_lyrics.gif)

## Usage

See [LDDC User Guide](https://github.com/chenmozhijin/LDDC/wiki)

## Acknowledgments

Some functionalities are implemented with reference to the following projects:

### Lyrics Decryption

[![Readme Card](https://github-readme-stats.vercel.app/api/pin/?username=WXRIW&repo=QQMusicDecoder)](https://github.com/WXRIW/QQMusicDecoder)
[![Readme Card](https://github-readme-stats.vercel.app/api/pin/?username=jixunmoe&repo=qmc-decode)](https://github.com/jixunmoe/qmc-decode)
[![Readme Card](https://github-readme-stats.vercel.app/api/pin/?username=parakeet-rs&repo=libparakeet)](https://github.com/parakeet-rs/libparakeet)

### Music Platform APIs

[![Readme Card](https://github-readme-stats.vercel.app/api/pin/?username=MCQTSS&repo=MCQTSS_QQMusic)](https://github.com/MCQTSS/MCQTSS_QQMusic)
