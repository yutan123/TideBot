import 'package:tide_bot/media_storage_policy.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

String argument(List<String> args, String key) => args[args.indexOf(key) + 1];

void main() {
  final mono = audioStorageArguments(1, 16000);
  check(
      argument(mono, '-c:a') == 'aac', 'Audio must be AAC in an M4A container');
  check(argument(mono, '-ac') == '1', 'Voice must stay mono');
  check(argument(mono, '-ar') == '16000', 'Do not upsample a voice recording');
  check(argument(mono, '-b:a') == '64k', 'Voice storage bitrate');
  final stereo = audioStorageArguments(2, 96000);
  check(argument(stereo, '-ac') == '2', 'Music must keep its stereo channels');
  check(argument(stereo, '-ar') == '48000', 'Bound storage sample rate');
  check(argument(stereo, '-b:a') == '96k', 'Stereo storage bitrate');
  for (final fps in [12.0, 23.976, 24.0, 25.0, 30.0]) {
    check(!videoStorageArguments(fps).contains('-r'),
        'Do not add frames to $fps fps video');
  }
  for (final fps in [50.0, 59.94, 60.0, 120.0]) {
    final args = videoStorageArguments(fps);
    check(argument(args, '-r') == '30', 'Cap high frame rate video at 30 fps');
    check(argument(args, '-c:v') == 'libx264', 'Use widely playable H.264');
    check(argument(args, '-pix_fmt') == 'yuv420p',
        'Use a compatible pixel format');
    check(args.contains('0:a:0?'),
        'Videos without an audio track must be supported');
  }
  check(mediaDurationMatches(60, 60.02), 'Allow normal encoder padding');
  check(!mediaDurationMatches(60, 50), 'Reject a truncated conversion');
  check(!mediaDurationMatches(10, 0), 'Reject empty output');
  check(!mediaDurationMatches(0, 0),
      'Unknown duration cannot authorize deletion');
  check(!mediaDurationMatches(double.nan, 10), 'Reject invalid input metadata');
  check(!mediaDurationMatches(10, double.infinity),
      'Reject invalid output metadata');
  print(
      'Media storage policy regression passed: audio quality, frame-rate limits, optional audio and truncation rejection.');
}
