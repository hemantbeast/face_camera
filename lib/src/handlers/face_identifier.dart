import 'dart:io';

import 'package:camera/camera.dart';
import 'package:face_camera/src/extension/nv21_converter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/detected_image.dart';

class FaceIdentifier {
  static Future<DetectedFace?> scanImage({
    required CameraImage cameraImage,
    required CameraController? controller,
    required FaceDetectorMode performanceMode,
  }) async {
    final orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

    DetectedFace? result;
    final face = await _detectFace(
      performanceMode: performanceMode,
      visionImage: _inputImageFromCameraImage(cameraImage, controller, orientations),
    );

    if (face != null) {
      result = face;
    }
    return result;
  }

  static InputImage? _inputImageFromCameraImage(CameraImage image, CameraController? controller, Map<DeviceOrientation, int> orientations) {
    // get image rotation
    // it is used in android to convert the InputImage from Dart to Java
    // `rotation` is not used in iOS to convert the InputImage from Dart to Obj-C
    // in both platforms `rotation` and `camera.lensDirection` can be used to compensate `x` and `y` coordinates on a canvas
    final camera = controller!.description;
    final sensorOrientation = camera.sensorOrientation;

    if (image.planes.isEmpty) {
      return null;
    }

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = orientations[controller.value.deviceOrientation];

      if (rotationCompensation == null) {
        return null;
      }

      if (camera.lensDirection == CameraLensDirection.front) {
        // front-facing
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        // back-facing
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }

    if (rotation == null) {
      return null;
    }

    // get image format
    final format = InputImageFormatValue.fromRawValue(image.format.raw);

    // validate format depending on platform
    // only supported formats:
    // * bgra8888 for iOS
    if (format == null || (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    if (Platform.isAndroid && format == InputImageFormat.yuv_420_888) {
      final bytes = image.convertYUV420ToNV21();

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    // compose InputImage using bytes
    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  static Future<DetectedFace?> _detectFace({required InputImage? visionImage, required FaceDetectorMode performanceMode}) async {
    if (visionImage == null) {
      return null;
    }

    final options = FaceDetectorOptions(
      enableLandmarks: true,
      enableTracking: true,
      enableClassification: true,
      performanceMode: performanceMode,
    );

    final faceDetector = FaceDetector(options: options);

    try {
      final List<Face> faces = await faceDetector.processImage(visionImage);
      final faceDetect = _extractFace(faces);
      return faceDetect;
    } catch (error) {
      debugPrint(error.toString());
      return null;
    }
  }

  static _extractFace(List<Face> faces) {
    final eulerValue = Platform.isAndroid ? 5 : 2;

    bool wellPositioned = faces.isNotEmpty;
    Face? detectedFace;

    for (Face face in faces) {
      // rect.add(face.boundingBox);
      detectedFace = face;

      // Head is rotated to the right rotY degrees
      if (face.headEulerAngleY! > eulerValue || face.headEulerAngleY! < -eulerValue) {
        wellPositioned = false;
      }

      // Head is tilted sideways rotZ degrees
      if (face.headEulerAngleZ! > eulerValue || face.headEulerAngleZ! < -eulerValue) {
        wellPositioned = false;
      }

      // Head is tilted sideways rotX degrees
      if (face.headEulerAngleX! > eulerValue || face.headEulerAngleX! < -eulerValue) {
        wellPositioned = false;
      }

      // If landmark detection was enabled with FaceDetectorOptions (mouth, ears,
      // eyes, cheeks, and nose available):
      final FaceLandmark? leftEar = face.landmarks[FaceLandmarkType.leftEar];
      final FaceLandmark? rightEar = face.landmarks[FaceLandmarkType.rightEar];
      final FaceLandmark? bottomMouth = face.landmarks[FaceLandmarkType.bottomMouth];
      final FaceLandmark? rightMouth = face.landmarks[FaceLandmarkType.rightMouth];
      final FaceLandmark? leftMouth = face.landmarks[FaceLandmarkType.leftMouth];
      final FaceLandmark? noseBase = face.landmarks[FaceLandmarkType.noseBase];

      if (leftEar == null || rightEar == null || bottomMouth == null || rightMouth == null || leftMouth == null || noseBase == null) {
        wellPositioned = false;
      }

      if (face.leftEyeOpenProbability != null) {
        if (face.leftEyeOpenProbability! < 0.5) {
          wellPositioned = false;
        }
      }

      if (face.rightEyeOpenProbability != null) {
        if (face.rightEyeOpenProbability! < 0.5) {
          wellPositioned = false;
        }
      }
    }

    return DetectedFace(wellPositioned: wellPositioned, face: detectedFace, isMultipleFaces: faces.length > 1);
  }
}
