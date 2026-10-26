import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../theme/app_prefs.dart';

/// 简单版听书控制器（Roadmap「听书」）：段落队列逐段朗读。
///
/// 平台差异规避：Android TextToSpeech 的 pause 语义不可靠，这里把
/// "暂停"实现为停在当前段（恢复/跳转时该段从头读）——段落本身短，
/// 体验可接受。语速/音调从设置读取，朗读中改设置下一段生效。
/// 语言跟随系统 TTS 引擎默认值（不做语言选择，见 Roadmap 边界）。
class TtsPlayer extends ChangeNotifier {
  TtsPlayer(this.paragraphs);

  /// 朗读段落队列（由 markdownToSpeechParagraphs 生成）。
  final List<String> paragraphs;

  FlutterTts? _engine;
  bool _disposed = false;
  bool _playing = false;
  bool _active = false; // 已开始且未停止/读完
  int _index = 0;

  /// 是否正在朗读（暂停中为 false）。
  bool get playing => _playing;

  /// 队列已开始且未停止/读完（控制面板显示"继续/从头"依据）。
  bool get active => _active;

  /// 当前段索引。
  int get index => _index;
  int get total => paragraphs.length;

  Future<FlutterTts> _getEngine() async {
    final t = _engine ??= FlutterTts();
    final prefs = AppPrefs.instance;
    // flutter_tts 的语速区间 0–1（≈0.5 正常语速），设置里存倍率 0.5–2.0
    await t.setSpeechRate(
      ((prefs?.ttsRate ?? 1.0) * 0.5).clamp(0.05, 1.0),
    );
    await t.setPitch((prefs?.ttsPitch ?? 1.0).clamp(0.5, 2.0));
    t.setCompletionHandler(_onUtteranceDone);
    t.setErrorHandler((msg) {
      if (_disposed) return;
      _playing = false;
      notifyListeners();
    });
    return t;
  }

  /// 当前段读完：自动接下一段，读完最后一段即收尾。
  void _onUtteranceDone() {
    if (_disposed || !_playing) return;
    if (_index + 1 >= paragraphs.length) {
      _playing = false;
      _active = false;
      _index = 0;
      notifyListeners();
      return;
    }
    _index++;
    notifyListeners();
    _speakCurrent();
  }

  Future<void> _speakCurrent() async {
    if (_disposed) return;
    final t = await _getEngine();
    if (_disposed || !_playing) return;
    await t.speak(paragraphs[_index]);
  }

  /// 开始/继续朗读：从 [index]（缺省 = 当前位置，未开始则第 0 段）。
  Future<void> start({int? index}) async {
    if (_disposed || paragraphs.isEmpty) return;
    final from = index ?? (_active ? _index : 0);
    _index = from.clamp(0, paragraphs.length - 1);
    _active = true;
    _playing = true;
    notifyListeners();
    await _speakCurrent();
  }

  /// 暂停：停在当前段，恢复时该段从头读。
  Future<void> pause() async {
    if (_disposed || !_playing) return;
    _playing = false;
    notifyListeners();
    (await _getEngine()).stop();
  }

  /// 下一句/上一段：播放中直接跳读，暂停中只移动位置。
  Future<void> next() => _jump(_index + 1);
  Future<void> prev() => _jump(_index - 1);

  Future<void> _jump(int i) async {
    if (_disposed || i < 0 || i >= paragraphs.length) return;
    _index = i;
    notifyListeners();
    if (_playing) await _speakCurrent();
  }

  /// 停止并复位到第 0 段。
  Future<void> stop() async {
    if (_disposed) return;
    _playing = false;
    _active = false;
    _index = 0;
    notifyListeners();
    (await _getEngine()).stop();
  }

  @override
  void dispose() {
    _disposed = true;
    _engine?.stop();
    super.dispose();
  }
}
