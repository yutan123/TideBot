import 'dart:async';
import 'dart:io';

import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:path_provider/path_provider.dart';

class LocalLlama {
  static final LocalLlama instance = LocalLlama._();
  LocalLlama._();

  LlamaController? _controller;
  String? _path;
  Future<void> _queue = Future<void>.value();

  Future<LlamaController> _ensureLoaded(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('本地 GGUF 文件不存在');
    }
    if (await file.length() < 1024 * 1024) {
      throw StateError('本地 GGUF 文件不完整');
    }
    if (_controller != null &&
        _path == path &&
        await _controller!.isModelLoaded()) {
      return _controller!;
    }

    final controller = LlamaController();
    await controller.loadModel(
      modelPath: path,
      threads: 4,
      contextSize: 2048,
      gpuLayers: 0,
    );
    if (!await controller.isModelLoaded()) {
      await controller.dispose();
      throw StateError('GGUF 模型加载失败');
    }

    final old = _controller;
    _controller = controller;
    _path = path;
    if (old != null) {
      try {
        await old.dispose();
      } catch (_) {}
    }
    return controller;
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
        final output = StringBuffer();
        await for (final token in controller.generateChat(
          messages: messages
              .map((message) => ChatMessage(
                    role: message['role'].toString(),
                    content: message['content'].toString(),
                  ))
              .toList(),
          maxTokens: 512,
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

  Future<String> pathFor(String id) async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$id.gguf';
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
