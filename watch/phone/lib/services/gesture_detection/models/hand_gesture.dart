enum HandGesture {
  thumbsUp,
  thumbsDown,
  openPalm,
  none,
}

extension HandGestureExtension on HandGesture {
  String get emoji {
    switch (this) {
      case HandGesture.thumbsUp:
        return '👍';
      case HandGesture.thumbsDown:
        return '👎';
      case HandGesture.openPalm:
        return '🖐';
      case HandGesture.none:
        return '❌';
    }
  }

  String get label {
    switch (this) {
      case HandGesture.thumbsUp:
        return 'THUMBS UP';
      case HandGesture.thumbsDown:
        return 'THUMBS DOWN';
      case HandGesture.openPalm:
        return 'OPEN PALM';
      case HandGesture.none:
        return 'NONE';
    }
  }
}
