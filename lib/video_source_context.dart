/// Identifies the audio source without asking the transcriber to infer speech
/// from frames. The chat request receives the frame mapping separately.
String videoAudioSourceContext(String videoId, {required bool isPreview}) {
  final source = videoId.trim().isEmpty ? '本条视频' : '视频 $videoId';
  return '这段音频提取自用户发送的$source，'
      '不是用户单独发送的聊天语音。后续聊天请求会提供同一视频的抽帧图片及本次转写，'
      '两者来自同一视频。${isPreview ? '画面仅为前40秒预览，音轨从原视频提取，不保证与每帧逐一对齐。' : ''}'
      '此请求只转写音轨中的人声，不推测画面、不补写听不清的内容。';
}

/// Uses the same one-based numbering as AIManager's current-image labels.
String videoFrameSourceContext(String videoId,
    {required int firstImageNumber, required int frameCount}) {
  if (frameCount == 0) return '';
  if (firstImageNumber < 1 || frameCount < 0) {
    throw ArgumentError('视频帧的图片编号和数量无效');
  }
  final labels = List.generate(
      frameCount, (index) => '[本轮图片#${firstImageNumber + index}]');
  return '视频 $videoId 的抽帧图片（按时间先后排列）：${labels.join('、')}。'
      '如提供本视频的音轨转写，它与这些图片来自同一个视频，请结合画面与声音理解；'
      '不得与其他视频或独立图片混淆。音轨转写不代表用户在向你直接说话，'
      '也不提供逐帧对应时间。';
}
