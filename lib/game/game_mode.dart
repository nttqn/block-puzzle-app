/// The two ways to play. Kept as its own tiny file since it's imported by
/// the engine, the score service (best score is tracked per mode), and both
/// the home screen's mode picker and the game screen.
enum GameMode {
  /// The original endless mode: place pieces, clear lines, no time
  /// pressure beyond running out of room for the tray's pieces.
  classic,

  /// A bomb tile appears on the board at all times; its row or column must
  /// be completed (clearing it) before its countdown reaches zero, or the
  /// run ends immediately regardless of whether pieces could still fit.
  survival,
}

extension GameModeLabel on GameMode {
  String get label {
    switch (this) {
      case GameMode.classic:
        return 'Classic';
      case GameMode.survival:
        return 'Survival';
    }
  }

  String get description {
    switch (this) {
      case GameMode.classic:
        return 'Clear lines at your own pace.';
      case GameMode.survival:
        return 'Defuse the bomb before time runs out!';
    }
  }
}
