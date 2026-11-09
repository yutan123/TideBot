import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'global_notice.dart';
import 'mimo_voice_clone.dart';
import 'mimo_audio_import.dart';
import 'theme.dart';
import 'android_selection_menu.dart';

class MimoVoiceWorkbench extends StatefulWidget {
  const MimoVoiceWorkbench(
      {super.key,
      this.initial,
      required this.model,
      required this.fetchModels});
  final Map<String, dynamic>? initial;
  final String model;
  final Future<void> Function(BuildContext, TextEditingController) fetchModels;
  @override
  State<MimoVoiceWorkbench> createState() => _MimoVoiceWorkbenchState();
}

class _MimoVoiceWorkbenchState extends State<MimoVoiceWorkbench> {
  final _player = AudioPlayer();
  Map<String, dynamic>? _sample;
  bool _busy = false;
  bool _playing = false;
  bool _fetchingModels = false;
  String? _error;
  Directory? _temporarySampleDirectory;
  int? _conversionSessionId;
  late final TextEditingController _model;
  late final StreamSubscription<void> _completion;

  @override
  void initState() {
    super.initState();
    _model = TextEditingController(
        text: widget.model.trim().isNotEmpty
            ? widget.model
            : widget.initial?['model']?.toString() ?? '');
    _sample = widget.initial == null ? null : Map.of(widget.initial!);
    _completion = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  Future<Map<String, dynamic>> _inspect(String path, String name) async {
    final file = File(path);
    validateMimoSampleSize(await file.length());
    final metadata = inspectMimoAudio(await _probe(path));
    return {
      'model': _model.text.trim(),
      'path': path,
      'name': name,
      ...metadata,
      'bytes': await file.length(),
    };
  }

  Future<Map<dynamic, dynamic>> _probe(String path) async {
    final session = await FFprobeKit.getMediaInformation(path)
        .timeout(const Duration(seconds: 30));
    final info = session.getMediaInformation()?.getAllProperties();
    if (info == null) {
      throw const FormatException('无法读取音频信息，请重新选择本机音频');
    }
    return info;
  }

  Future<void> _convert(List<String> arguments) async {
    final done = Completer<bool>();
    final session =
        await FFmpegKit.executeWithArgumentsAsync(arguments, (finished) async {
      try {
        final success = ReturnCode.isSuccess(await finished.getReturnCode());
        if (!done.isCompleted) done.complete(success);
      } catch (_) {
        if (!done.isCompleted) done.complete(false);
      }
    });
    _conversionSessionId = session.getSessionId();
    try {
      if (!mounted) {
        await FFmpegKit.cancel(session.getSessionId());
        throw const FormatException('音频转换已取消');
      }
      final success = await done.future.timeout(const Duration(seconds: 90));
      if (!success) {
        throw const FormatException('无法转换此音频，请选择其他录音文件');
      }
    } on TimeoutException {
      await FFmpegKit.cancel(session.getSessionId());
      await done.future
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      throw const FormatException('音频转换超时，请选择较短的录音');
    } finally {
      _conversionSessionId = null;
    }
  }

  Future<void> _removeTemporary(Directory? directory) async {
    if (directory == null) return;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException catch (error) {
      debugPrint('MiMo temporary audio cleanup failed: $error');
    }
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    Directory? candidate;
    try {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: mimoAudioExtensions);
      if (result == null || !mounted) return;
      final picked = result.files.single;
      if (picked.path == null) throw const FormatException('无法读取所选音频');
      candidate =
          await (await getTemporaryDirectory()).createTemp('mimo_voice_');
      final sample = await prepareMimoReferenceAudio(
        sourcePath: picked.path!,
        sourceName: picked.name,
        directory: candidate,
        probe: _probe,
        convert: _convert,
      );
      if (!mounted) return;
      final previous = _temporarySampleDirectory;
      setState(() {
        _sample = sample;
        _temporarySampleDirectory = candidate;
      });
      candidate = null;
      await _removeTemporary(previous);
    } catch (error) {
      _showError(error, '音频导入失败');
    } finally {
      await _removeTemporary(candidate);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    if (_sample == null) return;
    if (_model.text.trim().isEmpty) {
      _showError(const FormatException('请填写支持音色克隆的模型名'), '无法应用');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _player.stop();
      final sample = {
        ..._sample!,
        ...await _inspect(
            _sample!['path'] as String, _sample!['name']?.toString() ?? '参考音频')
      };
      final bytes = await File(sample['path'] as String).readAsBytes();
      validateMimoSampleSize(bytes.length);
      final root = await getApplicationSupportDirectory();
      final folder = Directory('${root.path}/mimo_voice_samples');
      await folder.create(recursive: true);
      final ext = sample['mime'] == 'audio/wav' ? 'wav' : 'mp3';
      final target = File('${folder.path}/${sha256.convert(bytes)}.$ext');
      if (!await target.exists()) {
        await target.writeAsBytes(bytes, flush: true);
      }
      sample['path'] = target.path;
      if (mounted) Navigator.pop(context, sample);
    } catch (error) {
      _showError(error, '无法应用克隆音色');
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _playing = false;
        });
    }
  }

  void _showError(Object error, String prefix) {
    debugPrint('MiMo audio error: $error');
    final message =
        error is FormatException ? error.message : '音频读取或转换失败，请重新选择本机音频';
    if (mounted) setState(() => _error = '$prefix：$message');
  }

  Future<void> _fetchModels() async {
    setState(() => _fetchingModels = true);
    try {
      await widget.fetchModels(context, _model);
    } finally {
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  Future<void> _preview() async {
    try {
      if (_playing) {
        await _player.stop();
      } else {
        await _player.play(DeviceFileSource(_sample!['path'] as String));
      }
      if (mounted) setState(() => _playing = !_playing);
    } catch (_) {
      if (mounted) setState(() => _playing = false);
      GlobalNotice.show('无法播放参考音频，请重新选择');
    }
  }

  @override
  void dispose() {
    _model.dispose();
    unawaited(_completion.cancel());
    unawaited(_releaseResources());
    super.dispose();
  }

  Future<void> _releaseResources() async {
    final sessionId = _conversionSessionId;
    if (sessionId != null) {
      try {
        await FFmpegKit.cancel(sessionId);
      } catch (error) {
        debugPrint('MiMo conversion cancellation failed: $error');
      }
    }
    try {
      await _player.dispose();
    } finally {
      await _removeTemporary(_temporarySampleDirectory);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return PopScope(
      canPop: !_busy && !_fetchingModels,
      child: Scaffold(
        backgroundColor: theme.bgColor,
        appBar: AppBar(
          title: const Text('MiMo 工作台'),
          backgroundColor: theme.bgColor,
          foregroundColor: theme.textStrong,
          actions: [
            TextButton(
              onPressed:
                  _busy || _fetchingModels || _sample == null ? null : _apply,
              child: Text('应用', style: TextStyle(color: theme.primary)),
            )
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Icon(Icons.graphic_eq_rounded, size: 56, color: theme.primary),
          const SizedBox(height: 20),
          Text('让熟悉的声音，陪你对话',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: theme.textStrong)),
          const SizedBox(height: 28),
          TextField(
            controller: _model,
            contextMenuBuilder: androidTextContextMenu,
            enabled: !_busy && !_fetchingModels,
            style: TextStyle(color: theme.textStrong, fontSize: 14),
            decoration: InputDecoration(
              labelText: '音色克隆模型',
              hintText: '手动输入或获取后选择',
              filled: true,
              fillColor: theme.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              suffixIcon: TextButton.icon(
                onPressed: _busy || _fetchingModels ? null : _fetchModels,
                icon: Icon(Icons.cloud_download_outlined,
                    size: 18, color: theme.primary),
                label: Text('获取', style: TextStyle(color: theme.primary)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('请使用支持音色克隆的模型；可手动输入新模型名称，或通过当前提供商获取。',
              style: TextStyle(fontSize: 12, color: theme.textWeak)),
          const SizedBox(height: 24),
          Text('参考音频',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.textStrong)),
          const SizedBox(height: 8),
          const Text(
              '支持 MP3、WAV、M4A、AAC、FLAC、OGG、OPUS、AMR、WMA、AIFF、CAF 等音频，选中后自动转换为 WAV。\n建议使用 5～30 秒清晰、无背景音乐的单人录音；转换后 Base64 编码须在 10 MB 以内。'),
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: _busy || _fetchingModels ? null : _pick,
              icon: const Icon(Icons.audio_file_outlined),
              label: Text(_sample == null ? '选择克隆音频' : '更换克隆音频')),
          if (_sample != null) ...[
            const SizedBox(height: 16),
            Text(_sample!['name']?.toString() ?? '参考音频',
                style: TextStyle(color: theme.textStrong)),
            if (_sample!['source_name'] != null)
              Text('已自动转换为 WAV', style: TextStyle(color: theme.textWeak)),
            Text(
                '${((_sample!['duration'] as num?) ?? 0).toStringAsFixed(1)} 秒 · ${(((_sample!['bytes'] as num?) ?? 0) / 1000000).toStringAsFixed(2)} MB'),
            TextButton.icon(
                onPressed: _busy ? null : _preview,
                icon: Icon(
                    _playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
                label: Text(_playing ? '停止' : '试听参考音频')),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: const TextStyle(color: Color(0xFFE74C3C))),
            ),
          if (_busy)
            const Padding(
                padding: EdgeInsets.all(20),
                child: Column(children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在读取并处理参考音频…')
                ])),
          const SizedBox(height: 24),
          const Text(
              '应用后返回提供商编辑页，再保存提供商。仅当音色为“克隆音色”时，每次合成会发送这份参考音频；切换普通音色时，请同时选择支持普通合成的模型。'),
        ]),
      ),
    );
  }
}
