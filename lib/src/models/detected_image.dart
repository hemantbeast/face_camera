import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class DetectedFace {
  const DetectedFace({
    required this.face,
    required this.wellPositioned,
    this.isMultipleFaces = false,
  });

  final Face? face;

  final bool wellPositioned;

  final bool isMultipleFaces;

  DetectedFace copyWith({Face? face, bool? wellPositioned, bool? isMultipleFaces}) {
    return DetectedFace(
      face: face ?? this.face,
      wellPositioned: wellPositioned ?? this.wellPositioned,
      isMultipleFaces: isMultipleFaces ?? this.isMultipleFaces,
    );
  }
}
