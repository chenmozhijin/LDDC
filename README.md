# LDDC

> 精准歌词(逐字歌词)下载解密转换

[![Codacy Badge](https://app.codacy.com/project/badge/Grade/015f636391584ffc82790ff7038da5ca)](https://app.codacy.com/gh/chenmozhijin/LDDC/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/chenmozhijin/LDDC/total)](https://github.com/chenmozhijin/LDDC/releases/latest)
[![Static Badge](https://img.shields.io/badge/Python-3.10%2B-brightgreen)](https://www.python.org/downloads/)
[![Static Badge](https://img.shields.io/badge/License-GPLv3-blue)](https://github.com/chenmozhijin/LDDC/blob/main/LICENSE)
[![release](https://img.shields.io/github/v/release/chenmozhijin/LDDC?color=blue)](https://github.com/chenmozhijin/LDDC/releases/latest)

## 功能

- [x] 根据歌曲名搜索歌词
- [x] 下载转换预览lrc歌词
- [x] 合并歌词：支持精准歌词原文、译文与罗马音合并
- [x] 保存歌词：支持保存为lrc格式,保存路径/文件名支持占位符

## 预览

![image](img/1.png)
![image](img/2.png)

## 使用方法

### 1.运行

#### 方式一:从[release](https://github.com/chenmozhijin/LDDC/releases)下载

> [release](https://github.com/chenmozhijin/LDDC/releases)中的版本是通过[nuitka](https://github.com/Nuitka/Nuitka)编译并用[Enigma Virtual Box](https://enigmaprotector.com/en/aboutvb.html)打包的exe

1. 下载[release](https://github.com/chenmozhijin/LDDC/releases)中最新版本的zip压缩包
2. 解压zip包
3. 运行`LDDC.exe`

#### 方式二:直接运行LDDC.py

> 需要安装python3.10+环境

1. 下载源代码
2. 安装依赖库

   ```bash
   pip install -r requirements.txt
   ```

3. 运行`LDDC.py`

### 2.使用

#### 搜索歌词

1. 输入歌曲名,点击搜索
2. 双击预览歌词

#### 合并歌词

0. 设置中修改合并顺序（直接拖动）
1. 左下角选择需要的歌词类型
2. 预览歌词时将显示合并后的歌词

#### 保存歌词

0. 设置中修改保存文件名格式
1. 选择保存路径,可输入占位符
2. 点击保存

## 感谢

部分功能实现参考了以下项目:  

### 歌词解密

[![Readme Card](https://github-readme-stats.vercel.app/api/pin/?username=WXRIW&repo=Lyricify-Lyrics-Helper)](https://github.com/WXRIW/Lyricify-Lyrics-Helper)

### 搜索api

[![Readme Card](https://github-readme-stats.vercel.app/api/pin/?username=MCQTSS&repo=MCQTSS_QQMusic)](https://github.com/MCQTSS/MCQTSS_QQMusic)
