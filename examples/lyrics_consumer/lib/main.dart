import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final Lyrics lyrics = await loadBundledLyrics();
  runApp(LyricsConsumerApp(lyrics: lyrics));
}

/// 仅使用 runtime 的公开本地来源读取内存歌词，不依赖 LDDC 应用配置或目录。
Future<Lyrics> loadBundledLyrics() {
  const String sample =
      '[00:00.00]LDDC lyrics package\n'
      '[00:03.20]Independent Flutter consumer\n';
  return createDefaultLocalLyricsProvider().getLyrics(
    LocalLyricsRequest(
      path: 'consumer_sample.lrc',
      data: Uint8List.fromList(utf8.encode(sample)),
    ),
  );
}

class LyricsConsumerApp extends StatelessWidget {
  const LyricsConsumerApp({super.key, required this.lyrics});

  final Lyrics lyrics;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: LyricsConsumerPage(lyrics: lyrics),
    );
  }
}

class LyricsConsumerPage extends StatefulWidget {
  const LyricsConsumerPage({super.key, required this.lyrics});

  final Lyrics lyrics;

  @override
  State<LyricsConsumerPage> createState() => _LyricsConsumerPageState();
}

class _LyricsConsumerPageState extends State<LyricsConsumerPage> {
  final TextEditingController _queryController = TextEditingController(
    text: 'Imagine',
  );
  final LyricsCloudSourceProvider _provider =
      createDefaultLrclibLyricsProvider();
  List<SongInfo> _results = const <SongInfo>[];
  String? _error;
  bool _searching = false;

  @override
  void dispose() {
    _queryController.dispose();
    if (_provider case final ClosableLyricsSourceProvider closable) {
      unawaited(closable.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String preview = LyricsPreviewComposer.buildPreviewText(
      lyrics: widget.lyrics,
      selectedLangs: const <String>['orig'],
      lyricsFormat: LyricsFormat.lineByLineLrc,
      offsetMs: 0,
      options: LyricsConvertOptions(),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Lyrics consumer')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    decoration: const InputDecoration(
                      labelText: 'LRCLIB search',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => unawaited(_search()),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _searching ? null : _search,
                  tooltip: 'Search',
                  icon: _searching
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                ),
              ],
            ),
          ),
          if (_error case final String error)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(error, style: TextStyle(color: Colors.red.shade700)),
            ),
          if (_results.isNotEmpty)
            SizedBox(
              height: 180,
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (BuildContext context, int index) {
                  final SongInfo song = _results[index];
                  return ListTile(
                    dense: true,
                    title: Text(song.fullTitle),
                    subtitle: Text(song.artistText),
                    trailing: Text(song.formattedDuration),
                  );
                },
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LyricsPreviewViewport(text: preview),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _search() async {
    final String keyword = _queryController.text.trim();
    if (keyword.isEmpty || _searching) {
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final APIResultList<SourceAware> result = await _provider.search(
        keyword: keyword,
        searchType: SearchType.song,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _results = result.whereType<SongInfo>().toList(growable: false);
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
        });
      }
    }
  }
}
