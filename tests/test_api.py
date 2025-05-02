# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from LDDC.common.models import SearchType
from LDDC.core.api.lyrics.kg import KGAPI
from LDDC.core.api.lyrics.lrclib import LrclibAPI
from LDDC.core.api.lyrics.ne import NEAPI
from LDDC.core.api.lyrics.qm import QMAPI


def test_neapi() -> None:
    neapi = NEAPI()
    songs = neapi.search("one's future", SearchType.SONG)
    assert len(songs) > 0
    song = songs[1]
    assert song.title
    lyrics = neapi.get_lyrics(song)
    assert lyrics

    songlists = neapi.search("Kud Wafter", SearchType.SONGLIST)
    assert len(songlists) > 0
    songlist = songlists[0]
    assert songlist.title
    songs = neapi.get_songlist(songlist)
    assert len(songs) > 0
    song = songs[0]
    assert song.title
    lyrics = neapi.get_lyrics(song)
    assert lyrics is not None

    albums = neapi.search("Kud Wafter Original SoundTrack", SearchType.ALBUM)
    assert len(albums) > 0
    album = albums[0]
    assert album.title
    songs = neapi.get_songlist(album)
    assert len(songs) > 0
    song = songs[0]
    assert song.title
    lyrics = neapi.get_lyrics(song)
    assert lyrics is not None


def test_qmapi() -> None:
    qmapi = QMAPI()

    songs = qmapi.search("one's future", SearchType.SONG)
    assert len(songs) > 0
    song = songs[1]
    assert song.title
    lyrics = qmapi.get_lyrics(song)
    assert lyrics

    songlists = qmapi.search("Kud Wafter", SearchType.SONGLIST)
    assert len(songlists) > 0
    songlist = songlists[0]
    assert songlist.title
    songs = qmapi.get_songlist(songlist)
    assert len(songs) > 0
    song = songs[0]
    assert song.title
    lyrics = qmapi.get_lyrics(song)
    assert lyrics is not None

    albums = qmapi.search("Kud Wafter Original SoundTrack", SearchType.ALBUM)
    assert len(albums) > 0
    album = albums[0]
    assert album.title
    songs = qmapi.get_songlist(album)
    assert len(songs) > 0
    song = songs[0]
    assert song.title
    lyrics = qmapi.get_lyrics(song)
    assert lyrics is not None


def test_kgapi() -> None:
    kgapi = KGAPI()

    songs = kgapi.search("アルカテイル", SearchType.SONG)
    assert len(songs) > 0
    song = songs[0]
    assert song.title
    lyrics = kgapi.get_lyrics(song)
    assert lyrics

    songlists = kgapi.search("Kud Wafter", SearchType.SONGLIST)
    assert len(songlists) > 0
    songlist = songlists[0]
    assert songlist.title
    songs = kgapi.get_songlist(songlist)
    assert len(songs) > 0
    song = songs[0]
    assert song.title
    lyrics = kgapi.get_lyrics(song)
    assert lyrics is not None

    albums = kgapi.search("Kud Wafter Original SoundTrack", SearchType.ALBUM)
    assert len(albums) > 0
    album = albums[0]
    assert album.title
    songs = kgapi.get_songlist(album)
    assert len(songs) > 0
    song = songs[0]
    assert song.title
    lyrics = kgapi.get_lyrics(song)
    assert lyrics is not None


def test_Lrclib() -> None:
    lrc_lib_api = LrclibAPI()

    songs = lrc_lib_api.search("アルカテイル", SearchType.SONG)
    assert len(songs) > 0
    song = songs[0]
    assert song.title
    lyrics = lrc_lib_api.get_lyrics(song)
    assert lyrics
