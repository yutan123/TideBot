import 'dart:math' as math;

/// Storage and request conversion share these limits, without upscaling.
List<String> audioStorageArguments(int channels, int sampleRate) => [
      '-vn',
      '-c:a',
      'aac',
      '-b:a',
      channels <= 1 ? '64k' : '96k',
      '-ac',
      '${channels.clamp(1, 2)}',
      '-ar',
      '${sampleRate.clamp(8000, 48000)}',
      '-movflags',
      '+faststart',
    ];

List<String> videoStorageArguments(double frameRate) => [
      '-map',
      '0:v:0',
      '-map',
      '0:a:0?',
      '-sn',
      '-dn',
      '-vf',
      "scale=w='if(gte(iw,ih),min(1920,iw),min(1080,iw))':h='if(gte(iw,ih),min(1080,ih),min(1920,ih))':force_original_aspect_ratio=decrease:force_divisible_by=2",
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '25',
      '-maxrate',
      '3M',
      '-bufsize',
      '6M',
      '-pix_fmt',
      'yuv420p',
      if (frameRate > 30) ...['-r', '30'],
      '-c:a',
      'aac',
      '-b:a',
      '96k',
      '-ac',
      '2',
      '-movflags',
      '+faststart',
    ];

bool mediaDurationMatches(double before, double after) =>
    before.isFinite &&
    after.isFinite &&
    before > 0 &&
    after > 0 &&
    (before - after).abs() <= math.max(0.25, before * .01);
