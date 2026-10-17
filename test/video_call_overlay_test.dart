import 'dart:async';

// Tests exercise the camera plugin's platform contract without real hardware.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/video_call_overlay.dart';

class FakeCallCamera extends CameraPlatform {
  final opened = <String>[];
  final disposed = <int>[];
  Completer<void>? initializing;
  bool failNext = false;
  Completer<XFile>? capturing;
  @override
  Future<XFile> takePicture(int cameraId) => capturing!.future;
  static const cameras = [
    CameraDescription(
        name: 'rear-wide',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90),
    CameraDescription(
        name: 'rear-tele',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90),
    CameraDescription(
        name: 'front',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 90),
  ];
  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;
  @override
  Future<int> createCamera(
      CameraDescription description, ResolutionPreset? resolutionPreset,
      {bool enableAudio = false}) async {
    opened.add(description.name);
    return opened.length;
  }

  @override
  Future<void> initializeCamera(int cameraId,
      {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {
    await initializing?.future;
    if (failNext) {
      failNext = false;
      throw CameraException('test', 'initialization failed');
    }
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(CameraInitializedEvent(
          cameraId, 640, 480, ExposureMode.auto, true, FocusMode.auto, true));
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => Stream.multi((_) {});
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  Future<void> dispose(int cameraId) async {
    disposed.add(cameraId);
  }

  @override
  Widget buildPreview(int cameraId) =>
      ColoredBox(key: ValueKey('camera-$cameraId'), color: Colors.black);
}

void main() {
  late CameraPlatform original;
  late FakeCallCamera camera;
  setUp(() {
    original = CameraPlatform.instance;
    camera = FakeCallCamera();
    CameraPlatform.instance = camera;
  });
  tearDown(() => CameraPlatform.instance = original);

  testWidgets(
      'flip waits for an in-flight frame capture before disposing its camera',
      (tester) async {
    final key = GlobalKey<VideoCallOverlayState>();
    await tester.pumpWidget(MaterialApp(home: VideoCallOverlay(key: key)));
    await tester.pumpAndSettle();
    camera.capturing = Completer<XFile>();
    final capture = key.currentState!.captureFrame();
    await tester.pump();
    final flip = key.currentState!.switchCamera();
    await tester.pump();
    expect(camera.disposed, isEmpty);
    camera.capturing!.completeError(CameraException('test', 'capture failed'));
    await tester.pumpAndSettle();
    expect(await capture, isNull);
    await flip;
    expect(camera.opened, ['front', 'rear-wide']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
      'backgrounding during initialization releases the camera and resumes safely',
      (tester) async {
    camera.initializing = Completer<void>();
    final key = GlobalKey<VideoCallOverlayState>();
    await tester.pumpWidget(MaterialApp(home: VideoCallOverlay(key: key)));
    await tester.pump();
    key.currentState!.didChangeAppLifecycleState(AppLifecycleState.inactive);
    camera.initializing!.complete();
    await tester.pump();
    await tester.pump();
    expect(camera.disposed, [1]);
    key.currentState!.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(camera.opened, ['front', 'front']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'flip always alternates front and rear, skipping extra rear lenses',
      (tester) async {
    final key = GlobalKey<VideoCallOverlayState>();
    await tester.pumpWidget(MaterialApp(home: VideoCallOverlay(key: key)));
    await tester.pumpAndSettle();
    final first = key.currentState!.switchCamera();
    final second = key.currentState!.switchCamera();
    await tester.pumpAndSettle();
    await Future.wait([first, second]);
    expect(camera.opened, ['front', 'rear-wide', 'front']);
    expect(camera.disposed, [1, 2]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'flip while initializing is queued, and disposal during a switch is safe',
      (tester) async {
    camera.initializing = Completer<void>();
    final key = GlobalKey<VideoCallOverlayState>();
    await tester.pumpWidget(MaterialApp(home: VideoCallOverlay(key: key)));
    await tester.pump();
    final flip = key.currentState!.switchCamera();
    camera.initializing!.complete();
    await tester.pumpAndSettle();
    await flip;
    expect(camera.opened, ['front', 'rear-wide']);
    camera.initializing = Completer<void>();
    final pending = key.currentState!.switchCamera();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    camera.initializing!.complete();
    await tester.pumpAndSettle();
    await pending;
    expect(camera.disposed, contains(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed camera initialization does not lock subsequent flips',
      (tester) async {
    final key = GlobalKey<VideoCallOverlayState>();
    await tester.pumpWidget(MaterialApp(home: VideoCallOverlay(key: key)));
    await tester.pumpAndSettle();
    camera.failNext = true;
    final failed = key.currentState!.switchCamera();
    await tester.pumpAndSettle();
    await failed;
    final retry = key.currentState!.switchCamera();
    await tester.pumpAndSettle();
    await retry;
    expect(camera.opened, ['front', 'rear-wide', 'rear-wide']);
    expect(find.text('摄像头启动失败'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
