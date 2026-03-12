import 'dart:async';

enum PrivacyLevel { high, medium, emergency }

class PrivacyController {
  final _privacyLevelController = StreamController<PrivacyLevel>.broadcast();
  PrivacyLevel _currentLevel = PrivacyLevel.high;
  bool _isSharing = false;

  Stream<PrivacyLevel> get privacyStream => _privacyLevelController.stream;
  bool get isSharingLocation => _isSharing;

  void startSharing() {
    // Only allow sharing if in navigation or SOS
    if (_currentLevel != PrivacyLevel.high) {
      _isSharing = true;
    }
  }

  void stopSharing() {
    _isSharing = false;
  }

  void setPrivacyLevel(PrivacyLevel level) {
    _currentLevel = level;
    _privacyLevelController.add(level);
    if (level == PrivacyLevel.high) {
      stopSharing();
    }
  }

  void dispose() {
    _privacyLevelController.close();
  }
}
