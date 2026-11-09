import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'global_notice.dart';
import 'mimo_voice_clone.dart';
import 'theme.dart';

class MimoVoiceWorkbench extends StatefulWidget {
  const MimoVoiceWorkbench({super.key, this.initial});
  final Map<String, dynamic>? initial;
  @override
  State<MimoVoiceWorkbench> createState() => _MimoVoiceWorkbenchState();
}

class _MimoVoiceWorkbenchState extends State<MimoVoiceWorkbench> {
  final _player = AudioPlayer();
  Map<String, dynamic>? _sample;
  bool _busy = false;
  bool _playing = false;
  late final StreamSubscription<void> _completion;

  @override
  void initState() {
    super.initState();
    _sample = widget.initial == null ? null : Map.of(widget.initial!);
    _completion = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  Future<Map<String, dynamic>> _inspect(String path, String name) async {
    final file = File(path);
    validateMimoSampleSize(await file.length());
    final session = await FFprobeKit.getMediaInformation(path)
        .timeout(const Duration(seconds: 30));
    final info = session.getMediaInformation();
    final duration = double.tryParse(info?.getDuration() ?? '') ?? 0;
    if (!duration.isFinite || duration < 5 || duration > 30) {
      throw const FormatException('参考音频时长必须为 5～30 秒');
    }
    final format = info?.getFormat() ?? '';
    final streams = info?.getStreams() ?? [];
    if (!streams.any((stream) => stream.getType() == 'audio') ||
        streams.any((stream) => stream.getType() == 'video') ||
        !(format.split(',').contains('mp3') ||
            format.split(',').contains('wav'))) {
      throw const FormatException('请选择有效的 MP3 或 WAV 音频文件');
    }
    return {
      'model': mimoCloneModel,
      'path': path,
      'name': name,
      'mime': format.split(',').contains('mp3') ? 'audio/mpeg' : 'audio/wav',
      'duration': duration,
      'bytes': await file.length(),
    };
  }

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      final result = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['mp3', 'wav']);
      if (result == null) return;
      final picked = result.files.single;
      if (picked.path == null) throw const FormatException('无法读取所选音频');
      final sample = await _inspect(picked.path!, picked.name);
      if (mounted) setState(() => _sample = sample);
    } catch (error) {
      GlobalNotice.show('音频选择失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    if (_sample == null) return;
    setState(() => _busy = true);
    try {
      await _player.stop();
      final sample = await _inspect(
          _sample!['path'] as String, _sample!['name']?.toString() ?? '参考音频');
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
      GlobalNotice.show('无法应用克隆音色：$error');
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _playing = false;
        });
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
    unawaited(_completion.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: theme.bgColor,
        appBar: AppBar(
          title: const Text('MiMo 工作台'),
          backgroundColor: theme.bgColor,
          foregroundColor: theme.textStrong,
          actions: [
            TextButton(
              onPressed: _busy || _sample == null ? null : _apply,
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
          DropdownButtonFormField<String>(
            initialValue: mimoCloneModel,
            decoration: const InputDecoration(
                labelText: '音色克隆模型', border: OutlineInputBorder()),
            isExpanded: true,
            items: const [
              DropdownMenuItem(
                  value: mimoCloneModel,
                  child: Text(mimoCloneModel, style: TextStyle(fontSize: 13)))
            ],
            onChanged: _busy ? null : (_) {},
          ),
          const SizedBox(height: 24),
          Text('参考音频',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.textStrong)),
          const SizedBox(height: 8),
          const Text(
              'MP3 / WAV · 5～30 秒 · 10 MB 以内\n编码后的数据也须在 10 MB 以内，建议使用清晰、无背景音乐的单人录音。'),
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.audio_file_outlined),
              label: Text(_sample == null ? '选择克隆音频' : '更换克隆音频')),
          if (_sample != null) ...[
            const SizedBox(height: 16),
            Text(_sample!['name']?.toString() ?? '参考音频',
                style: TextStyle(color: theme.textStrong)),
            Text(
                '${((_sample!['duration'] as num?) ?? 0).toStringAsFixed(1)} 秒 · ${(((_sample!['bytes'] as num?) ?? 0) / 1000000).toStringAsFixed(2)} MB'),
            TextButton.icon(
                onPressed: _busy ? null : _preview,
                icon: Icon(
                    _playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
                label: Text(_playing ? '停止' : '试听参考音频')),
          ],
          if (_busy)
            const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator())),
          const SizedBox(height: 24),
          const Text(
              '应用后返回提供商编辑页，再保存提供商。仅当音色为“克隆音色”时，每次合成会发送这份参考音频；修改音色即可恢复普通合成。'),
        ]),
      ),
    );
  }
}
