import 'dart:async';
import 'dart:io';

import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log_service.dart';

class LocalLlama {
  static const int contextSize = 768;
  static const int maxOutputTokens = 128;
  static final LocalLlama instance = LocalLlama._();
  LocalLlama._();

  LlamaController? _controller;
  String? _path;
  Future<void> _queue = Future<void>.value();

  Future<LlamaController> _ensureLoaded(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('本地 GGUF 文件不存在，请到「本地模型」页重新下载后再试');
    }
    final size = await file.length();
    if (size < 1024 * 1024) {
      throw StateError(
          '本地 GGUF 文件不完整（仅 ${(size / 1024 / 1024).toStringAsFixed(1)} MB）');
    }
    // GGUF 魔数校验：所有 llama.cpp 可加载的 GGUF 文件都以 ASCII "GGUF" 开头，
    // 下载中断/续传拼接错误等导致的损坏文件会在此处被尽早拦截，避免 native 崩溃。
    await _validateGgufMagic(file);
    if (_controller != null &&
        _path == path &&
        await _controller!.isModelLoaded()) {
      return _controller!;
    }

    final controller = LlamaController();
    LlamaController? loaded;
    try {
      AppLogService.instance.add(
        'LOCAL_LLAMA',
        '加载模型：${file.path.split(Platform.pathSeparator).last}，'
            'size=${(size / 1024 / 1024).toStringAsFixed(1)}MB，context=$contextSize',
      );
      await controller.loadModel(
        modelPath: path,
        threads: 1,
        contextSize: contextSize,
        gpuLayers: 0,
      );
      if (!await controller.isModelLoaded()) {
        throw StateError('GGUF 模型加载回执异常');
      }
      AppLogService.instance.add('LOCAL_LLAMA', '模型加载完成，开始准备推理');
      loaded = controller;
    } catch (e) {
      await controller.dispose();
      // 若文件损坏到 native 无法解析，删除以便用户重新下载；同时给出明确提示。
      final msg = '本地模型加载失败（$e）。建议删除后在「本地模型」页重新下载。';
      final magicOk = await _tryReadGgufMagic(file);
      if (!magicOk) {
        try {
          await file.delete();
        } catch (_) {}
        throw StateError('$msg 已自动清理损坏文件。');
      }
      throw StateError(msg);
    }

    final old = _controller;
    _controller = loaded;
    _path = path;
    if (old != null) {
      try {
        await old.dispose();
      } catch (_) {}
    }
    return loaded;
  }

  /// 校验 GGUF 头部魔数（"GGUF"），不完整即判定损坏。
  Future<void> _validateGgufMagic(File file) async {
    if (!await _tryReadGgufMagic(file)) {
      throw StateError('GGUF 文件头部损坏或下载不完整，请删除后重新下载。');
    }
  }

  /// 尝试读取文件头部 4 字节是否为 "GGUF"。
  Future<bool> _tryReadGgufMagic(File file) async {
    try {
      final raf = await file.open();
      try {
        final head = await raf.read(4);
        return head.length == 4 &&
            head[0] == 0x47 && // G
            head[1] == 0x47 && // G
            head[2] == 0x55 && // U
            head[3] == 0x46; // F
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  Future<String> generate({
    required String path,
    required List<Map<String, dynamic>> messages,
  }) {
    final result = Completer<String>();
    // A failed request must not poison the serialized native queue; otherwise
    // every later local-model retry would be skipped.
    _queue = _queue.catchError((_) {}).then((_) async {
      try {
        final controller = await _ensureLoaded(path);
        final safeMessages = _fitMessages(messages);
        AppLogService.instance.add(
            'LOCAL_LLAMA',
            '开始推理：${File(path).path.split(Platform.pathSeparator).last}，'
                'context=$contextSize，messages=${safeMessages.length}，'
                'chars=${safeMessages.fold<int>(0, (sum, item) => sum + item['content'].toString().length)}');
        final output = StringBuffer();
        await for (final token in controller.generateChat(
          messages: safeMessages
              .map((message) => ChatMessage(
                    role: message['role'].toString(),
                    content: message['content'].toString(),
                  ))
              .toList(),
          maxTokens: maxOutputTokens,
          temperature: 0.7,
          topP: 0.9,
          topK: 40,
          minP: 0.05,
          typicalP: 1.0,
          repeatPenalty: 1.1,
          frequencyPenalty: 0.0,
          presencePenalty: 0.0,
          repeatLastN: 64,
          mirostat: 0,
          mirostatTau: 5.0,
          mirostatEta: 0.1,
          penalizeNewline: true,
        )) {
          output.write(token);
        }
        if (output.isEmpty) {
          throw StateError('本地模型未返回内容');
        }
        result.complete(output.toString());
      } catch (error, stack) {
        if (!result.isCompleted) {
          result.completeError(error, stack);
        }
      }
    });
    return result.future;
  }

  List<Map<String, dynamic>> _fitMessages(List<Map<String, dynamic>> messages) {
    // Keep generation headroom inside the native context. Character budgeting is
    // intentionally conservative for mixed Chinese/English prompts.
    const maxInputChars = 1500;
    final fitted = <Map<String, dynamic>>[];
    var remaining = maxInputChars;
    for (final message in messages.reversed) {
      final content = message['content']?.toString().trim() ?? '';
      if (content.isEmpty || remaining <= 0) continue;
      final clipped = content.length <= remaining
          ? content
          : content.substring(content.length - remaining);
      fitted.add(
          {'role': message['role']?.toString() ?? 'user', 'content': clipped});
      remaining -= clipped.length;
    }
    return fitted.reversed.toList();
  }

  Future<String> pathFor(String id) async {
    final directory = await getApplicationDocumentsDirectory();
    final expected = File('${directory.path}/$id.gguf');
    if (await expected.exists()) return expected.path;

    // Older releases persisted a selectable file name instead of the logical
    // model id. Accept both formats and report the resolved path accurately.
    final direct = File(id);
    if (await direct.exists()) return direct.path;
    final basename = id.split(RegExp(r'[/\\]')).last;
    final named = File('${directory.path}/$basename');
    if (await named.exists()) return named.path;

    final candidates = await directory
        .list()
        .where((entry) =>
            entry is File && entry.path.toLowerCase().endsWith('.gguf'))
        .cast<File>()
        .toList();
    final normalized = id.toLowerCase().replaceAll('.gguf', '');
    for (final file in candidates) {
      final name = file.path.split(Platform.pathSeparator).last.toLowerCase();
      if (name.replaceAll('.gguf', '') == normalized ||
          name.contains(normalized) ||
          normalized.contains(name.replaceAll('.gguf', ''))) {
        return file.path;
      }
    }
    throw FileSystemException('找不到已下载的本地模型文件', expected.path);
  }

  /// 真实验证模型能否被当前 Android native runtime 加载。
  /// 只执行 load → isModelLoaded → dispose，不会生成文本，也不会保留内存。
  Future<void> validateModel(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('找不到模型文件', path);
    }
    await _validateGgufMagic(file);
    final controller = LlamaController();
    try {
      // Native validation only proves the GGUF can be opened. Keep runtime
      // settings identical so a successfully verified file is not later loaded
      // with a larger, unsafe context during chat.
      await controller.loadModel(
        modelPath: path,
        threads: 1,
        contextSize: contextSize,
        gpuLayers: 0,
      );
      if (!await controller.isModelLoaded()) {
        throw StateError('Native 引擎未确认模型已加载');
      }
    } catch (e) {
      throw StateError('此模型无法被当前设备的本地推理引擎加载：$e');
    } finally {
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    _path = null;
    if (controller != null) {
      await controller.dispose();
    }
  }
}
