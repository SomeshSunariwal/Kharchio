import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final profilePhotoDirectoryProvider = FutureProvider<Directory>((ref) async {
  final directory = Directory(
    '${(await getApplicationSupportDirectory()).path}/profile',
  );
  await directory.create(recursive: true);
  return directory;
});

class UserProfile {
  final String name, photoPath;
  const UserProfile({this.name = 'Budget Tracker', this.photoPath = ''});
}

final userProfileProvider =
    AsyncNotifierProvider<UserProfileStore, UserProfile>(UserProfileStore.new);

/// Profile data lives entirely in private files, separate from expense SQLite.
class UserProfileStore extends AsyncNotifier<UserProfile> {
  Future<void> _pending = Future.value();

  @override
  Future<UserProfile> build() async {
    final directory = await ref.watch(profilePhotoDirectoryProvider.future);
    final file = File.fromUri(directory.uri.resolve('profile.json'));
    if (!await file.exists()) return const UserProfile();
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final name = (json['name'] as String?)?.trim();
    final photo = json['photo'] as String? ?? '';
    return UserProfile(
      name: name == null || name.isEmpty ? 'Budget Tracker' : name,
      photoPath: RegExp(r'^avatar-\d+\.png$').hasMatch(photo)
          ? File.fromUri(directory.uri.resolve(photo)).path
          : '',
    );
  }

  Future<void> saveName(String value) {
    final name = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty || name.length > 50) {
      throw ArgumentError('Enter a name between 1 and 50 characters.');
    }
    return _update(
      (current) => UserProfile(name: name, photoPath: current.photoPath),
    );
  }

  Future<void> savePhoto(String path) =>
      _update((current) => UserProfile(name: current.name, photoPath: path));

  Future<void> _update(UserProfile Function(UserProfile) change) {
    final task = _pending.then((_) async {
      final current = await future;
      final next = change(current);
      final directory = await ref.read(profilePhotoDirectoryProvider.future);
      if (next.photoPath.isNotEmpty &&
          File(next.photoPath).parent.absolute.uri != directory.absolute.uri) {
        throw ArgumentError(
          'Profile images must be stored in private profile storage.',
        );
      }
      final file = File.fromUri(directory.uri.resolve('profile.json'));
      final partial = File('${file.path}.partial');
      await partial.writeAsString(
        jsonEncode({
          'name': next.name,
          'photo': next.photoPath.isEmpty
              ? ''
              : File(next.photoPath).uri.pathSegments.last,
        }),
        flush: true,
      );
      await partial.rename(file.path);
      if (ref.mounted) state = AsyncData(next);
    });
    _pending = task.catchError((Object _) {});
    return task;
  }
}
