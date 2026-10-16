import 'dart:async';
import 'package:flutter/foundation.dart';

/// Prevent a rapid second tap from starting recording after Send becomes Mic.
/// Sending additional text and stopping an existing recording stay available.
class SendVoiceCooldown extends ChangeNotifier {
  static const duration = Duration(seconds: 2);
  Timer? _timer;
  bool _blocked = false;
  bool get isBlocked => _blocked;

  void markSend() {
    _timer?.cancel();
    _blocked = true;
    _timer = Timer(duration, () {
      _blocked = false;
      _timer = null;
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
