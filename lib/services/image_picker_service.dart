import 'dart:io';
import 'package:image_picker/image_picker.dart';

class ImagePickerService {
  static final ImagePicker _picker = ImagePicker();

  /// Picks multiple images from the gallery and returns them as a List of [File].
  static Future<List<File>> pickImages() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage();
      return pickedFiles.map((xFile) => File(xFile.path)).toList();
    } catch (e) {
      // In a real app, you might want more robust logging/error handling.
      return [];
    }
  }

  /// Picks a single image from the camera.
  static Future<File?> pickFromCamera() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.camera);
      if (pickedFile != null) {
        return File(pickedFile.path);
      }
    } catch (e) {
      return null;
    }
    return null;
  }
}
