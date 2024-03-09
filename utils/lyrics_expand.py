from utils.lyrics import Lyrics


def merge_lyrics(lyrics1: Lyrics, lyrics2: Lyrics) -> Lyrics:
    """
    合并两个Lyrics对象
    """
    if lyrics1.lrc_isverbatim["orig"] is True:
        pass
    elif lyrics2.lrc_isverbatim["orig"] is True:
        lyrics1 = lyrics2
        lyrics2 = lyrics1
    else:
        # 无法继续
        pass
    #    return lyrics1
    merged_lyrics = lyrics1.copy()

    def merge_verbatim(lyric1: list[tuple[int, int, list[tuple[int, int, str]]]],
                       lyric2: list[tuple[int, int | None, list[tuple[int, int | None, str]]]]) -> list[tuple[int, int, list[tuple[int, int, str]]]]:
        matched_words = []
        merged_lyric = []
        for index2, line2 in enumerate(lyric2):
            line2_starttime = line2[0]
            line2_endtime = line2[1]
            merged_lyric.append((line2_starttime, line2_endtime, []))
            for index1, line1 in enumerate(lyric1):
                line1_starttime = line1[0]
                line1_endtime = line1[1]
                if line2_starttime < line1_endtime or line2_endtime > line1_starttime:
                    continue
                for index_w, word in enumerate(line1[2]):
                    if word in matched_words:
                        continue
                    word_starttime = word[0]
                    word_endtime = word[1]
                    word_text = word[2]
                    if (line2_starttime <= word_starttime and word_endtime <= line2_endtime):  # 之中
                        if (line2_starttime <= word_endtime <= line2_endtime):
                            merged_lyric.append((word_starttime, word_endtime, word_text))
                            matched_words.append(word)
                        elif (word_endtime > line2_endtime):
                            merged_lyric.append((word_starttime, line2_endtime, word_text))
                            matched_words.append(word)
                    elif (word_starttime < line2_starttime and  # 在前面
                          abs(line2_starttime - word_starttime) < 500 and  # 小于500ms
                          ((word_text in line2[2] and
                           word_text not in lyric2[index2 - 1][2]) or  # 上一行没有,本行有
                           (len(line1[2]) != index_w + 1 and word_text + line1[2][index_w + 1] in line2[2] and
                           word_text + line1[2][index_w + 1] not in lyric2[index2 - 1][2]) or  # 与后面一个字符上一行没有,本行有
                           (word_text in lyric1[index1 - 1] and
                            word_text in line2[2] and
                            abs(line2_starttime - word_starttime) < abs(lyric2[index2 - 1][2][1] - word_endtime))
                           )):  # 原本上一行就有,但时间更近
                        merged_lyric.append((line2_starttime, word_endtime, word_text))
                        matched_words.append(word)
                    elif (line2_endtime < word_endtime and  # 在后面
                          abs(line2_endtime - word_endtime) < 500 and  # 小于500ms
                          ((word_text in line2[2] and
                           word_text not in lyric2[index2 + 1][2]) or  # 下一行没有,本行有
                           (index_w - 1 >= 0 and word_text + line1[2][index_w - 1] in line2[2] and
                           word_text + line1[2][index_w - 1] not in lyric2[index2 + 1][2]) or  # 与前面一个字符下一行没有,本行有
                           (word_text in lyric1[index1 + 1] and
                            word_text in line2[2] and
                            abs(line2_endtime - word_endtime) < abs(lyric2[index2 + 1][2][0] - word_starttime))
                           )):  # 原本下一行就有,但时间更近
                        merged_lyric.append((word_starttime, line2_endtime, word_text))
                        matched_words.append(word)

        if len(matched_words) == 0:
            return None

        words = []
        for line in lyric1:
            words.extend(line[2])

        i = 0
        while len(matched_words) == len(words):
            if i == len(words):
                i = 0
            word = words[i]
            if word not in matched_words:
                next_word = words[i + 1] if i != len(words) - 1 else None
                previous_word = words[i - 1] if i != 0 else None
                if next_word and previous_word:
                    if next_word in matched_words and previous_word in matched_words:
                        if abs(next_word[0] - word[1]) < abs(previous_word[1] - word[0]):
                            merged_lyric.append((word[0], next_word[1], word[2]))
                            matched_words.append(word)
                        else:
                            merged_lyric.append((previous_word[0], word[1], word[2]))
                            matched_words.append(word)
                    elif next_word in matched_words:
                        merged_lyric.append((word[0], next_word[1], word[2]))
                        matched_words.append(word)
                    elif previous_word in matched_words:
                        merged_lyric.append((previous_word[0], word[1], word[2]))
                        matched_words.append(word)
                elif next_word and next_word in matched_words:
                    merged_lyric.append((word[0], next_word[1], word[2]))
                    matched_words.append(word)
                elif previous_word and previous_word in matched_words:
                    merged_lyric.append((previous_word[0], word[1], word[2]))
                    matched_words.append(word)
            i += 1

        for line in merged_lyric:
            line_starttime = line[0]
            line_endtime = line[1]
            for index, word in enumerate(line[2]):
                word_starttime = word[0]
                word_endtime = word[1]
                previous_word_endtime = line[2][index - 1][1] if index > 0 else None
                next_word_starttime = line[2][index + 1][0] if index < len(line[2]) - 1 else None
                if word_starttime < line_starttime:
                    word_starttime = line_starttime
                if word_endtime > line_endtime:
                    word_endtime = line_endtime
                if previous_word_endtime and word_starttime < previous_word_endtime:
                    word_starttime = previous_word_endtime
                if next_word_starttime and word_endtime > next_word_starttime:
                    word_endtime = next_word_starttime

        return merged_lyric

    if "ts" not in lyrics1 and "ts" in lyrics2:
        merged_lyrics["orig"] = merge_verbatim(lyrics1["orig"], lyrics2["orig"])
        merged_lyrics["ts"] = lyrics2["ts"]

        if "roma" not in lyrics1 and "roma" in lyrics2:
            merged_lyrics["roma"] = lyrics2["roma"]

        elif "roma" in lyrics1 and "roma" not in lyrics2:
            merged_lyrics["roma"] = merge_verbatim(lyrics1["roma"], lyrics2["orig"])

        elif "roma" in lyrics1 and "roma" in lyrics2:
            if lyrics1.lrc_isverbatim["roma"] is True and lyrics1.lrc_isverbatim["roma"] is False:
                merged_lyrics["roma"] = merge_verbatim(lyrics1["roma"], lyrics2["orig"])
            else:
                merged_lyrics["roma"] = lyrics2["roma"]
    return merged_lyrics
