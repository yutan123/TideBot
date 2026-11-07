import 'package:tide_bot/video_source_context.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  // Two independent images precede two videos in the same chat request.
  final first =
      videoFrameSourceContext('VID_A', firstImageNumber: 3, frameCount: 2);
  final second =
      videoFrameSourceContext('VID_B', firstImageNumber: 5, frameCount: 3);
  check(first.contains('VID_A') && !first.contains('VID_B'), '第一段视频编号错误');
  check(first.contains('[本轮图片#3]、[本轮图片#4]'), '第一段视频帧编号错误');
  check(!first.contains('[本轮图片#2]') && !first.contains('[本轮图片#5]'),
      '视频帧混入独立图片或其他视频');
  check(
      second.contains('VID_B') && second.contains('[本轮图片#5]、[本轮图片#6]、[本轮图片#7]'),
      '第二段视频帧编号错误');
  check(second.contains('同一个视频'), '缺少音画关联');
  check(
      videoFrameSourceContext('VID_MODEL', firstImageNumber: 1, frameCount: 0)
          .isEmpty,
      '原视频模型模式不应虚构帧关联');

  final audio = videoAudioSourceContext('VID_A', isPreview: false);
  check(audio.contains('VID_A') && audio.contains('同一视频'), '转写请求缺少视频来源');
  check(audio.contains('只转写音轨中的人声'), '转写请求不应变成视频描述请求');
  check(!audio.contains('前40秒'), '短视频不应标记为预览');
  final preview = videoAudioSourceContext('VID_B', isPreview: true);
  check(preview.contains('画面仅为前40秒预览') && preview.contains('音轨从原视频提取'),
      '预览不能把原视频音轨误标为前40秒');
  check(videoAudioSourceContext('', isPreview: false).contains('本条视频'),
      '其他调用方未提供编号时仍须说明来源');
  print('Video source context checks passed.');
}
