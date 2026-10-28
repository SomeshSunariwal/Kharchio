import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/profile_store.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

final profileImagePickerProvider = Provider<ImagePicker>(
  (ref) => ImagePicker(),
);

class UserProfileCard extends ConsumerStatefulWidget {
  const UserProfileCard({super.key});
  @override
  ConsumerState<UserProfileCard> createState() => _UserProfileCardState();
}

class _UserProfileCardState extends ConsumerState<UserProfileCard> {
  final name = TextEditingController();
  bool editingName = false, savingName = false, changingPhoto = false;
  String? nameError;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) Future.microtask(_recoverPhoto);
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _recoverPhoto() async {
    var restoring = false;
    try {
      final lost = await ref
          .read(profileImagePickerProvider)
          .retrieveLostData();
      if (!mounted || changingPhoto || lost.isEmpty) return;
      if (lost.files?.isNotEmpty == true) {
        await ref.read(userProfileProvider.future);
        if (!mounted) return;
        restoring = true;
        setState(() => changingPhoto = true);
        await _storePhoto(lost.files!.first);
      } else if (lost.exception != null) {
        throw lost.exception!;
      }
    } catch (_) {
      if (mounted) {
        notice(
          context,
          'Could not restore the selected photo. Please choose it again.',
          isError: true,
        );
      }
    } finally {
      if (restoring && mounted) setState(() => changingPhoto = false);
    }
  }

  Future<void> _editPhoto() async {
    if (changingPhoto) return;
    final hasPhoto = ref
        .read(userProfileProvider)
        .requireValue
        .photoPath
        .isNotEmpty;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: green),
              title: const Text('Choose photo'),
              onTap: () => Navigator.pop(context, 'choose'),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: red),
                title: const Text('Remove photo'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null || changingPhoto) return;
    setState(() => changingPhoto = true);
    try {
      if (action == 'remove') {
        final old = ref.read(userProfileProvider).requireValue.photoPath;
        final directory = await ref.read(profilePhotoDirectoryProvider.future);
        if (!mounted) return;
        await ref.read(userProfileProvider.notifier).savePhoto('');
        await _deleteOwnedPhoto(old, directory);
      } else {
        final picked = await ref
            .read(profileImagePickerProvider)
            .pickImage(
              source: ImageSource.gallery,
              maxWidth: 1024,
              maxHeight: 1024,
              imageQuality: 85,
              requestFullMetadata: false,
            );
        if (picked != null && mounted) await _storePhoto(picked);
      }
    } catch (_) {
      if (mounted) {
        notice(
          context,
          'Could not update your photo. Please choose another image and try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => changingPhoto = false);
    }
  }

  Future<void> _storePhoto(XFile picked) async {
    final settings = ref.read(userProfileProvider.notifier);
    final old = ref.read(userProfileProvider).requireValue.photoPath;
    final directory = await ref.read(profilePhotoDirectoryProvider.future);
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('Invalid profile image.');
    }
    final codec = await ui.instantiateImageCodec(bytes);
    ui.Image? image;
    File? saved;
    try {
      image = (await codec.getNextFrame()).image;
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      if (encoded == null) {
        throw const FormatException('Invalid profile image.');
      }
      saved = File.fromUri(
        directory.uri.resolve(
          'avatar-${DateTime.now().microsecondsSinceEpoch}.png',
        ),
      );
      await saved.writeAsBytes(
        encoded.buffer.asUint8List(
          encoded.offsetInBytes,
          encoded.lengthInBytes,
        ),
        flush: true,
      );
      try {
        await settings.savePhoto(saved.path);
      } catch (_) {
        await saved.delete();
        rethrow;
      }
      await _deleteOwnedPhoto(old, directory);
    } finally {
      image?.dispose();
      codec.dispose();
    }
  }

  Future<void> _deleteOwnedPhoto(String path, Directory directory) async {
    if (path.isEmpty ||
        File(path).parent.absolute.uri != directory.absolute.uri) {
      return;
    }
    try {
      final old = File(path);
      if (await old.exists()) await old.delete();
    } on FileSystemException {
      /* An unused old file can be cleaned up later. */
    }
  }

  void _editName() {
    name.text = ref.read(userProfileProvider).requireValue.name;
    name.selection = TextSelection.collapsed(offset: name.text.length);
    setState(() {
      editingName = true;
      nameError = null;
    });
  }

  Future<void> _saveName() async {
    if (savingName) return;
    if (name.text.trim().isEmpty) {
      setState(() => nameError = 'Enter your name.');
      return;
    }
    setState(() {
      savingName = true;
      nameError = null;
    });
    try {
      await ref.read(userProfileProvider.notifier).saveName(name.text);
      if (mounted) {
        FocusScope.of(context).unfocus();
        setState(() => editingName = false);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => nameError = 'Could not save your name. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => savingName = false);
    }
  }

  ButtonStyle get _nameActionStyle => TextButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: EdgeInsets.zero,
    textStyle: const TextStyle(fontSize: 12),
  );

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(userProfileProvider);
    final profile = profileState.value ?? const UserProfile();
    final loading = profileState.isLoading || profileState.hasError;
    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(28),
    );
    return SurfaceCard(
      color: context.appColors.tint,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Change profile photo',
            child: Material(
              color: context.appColors.surface,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const Key('profile-photo'),
                onTap: changingPhoto || loading ? null : _editPhoto,
                customBorder: shape,
                child: SizedBox.square(
                  dimension: 72,
                  child: changingPhoto
                      ? const Center(
                          child: SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            if (profile.photoPath.isNotEmpty)
                              Image.file(
                                File(profile.photoPath),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const AppIcon(size: 72),
                              )
                            else
                              const AppIcon(size: 72),
                            Positioned(
                              right: 5,
                              bottom: 5,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: context.appColors.surface,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(3),
                                  child: Icon(
                                    Icons.add_a_photo_outlined,
                                    size: 12,
                                    color: green,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (editingName) ...[
                  SizedBox(
                    height: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: nameError == null ? green : red,
                          width: 1,
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextField(
                              controller: name,
                              autofocus: true,
                              enabled: !savingName,
                              maxLength: 50,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _saveName(),
                              style: const TextStyle(
                                fontSize: 24,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Your name',
                                counterText: '',
                                isCollapsed: true,
                                filled: false,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                              ),
                            ),
                          ),
                          if (nameError != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Text(
                                nameError!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  height: 1,
                                  color: red,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 24,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Row(
                        children: [
                          TextButton(
                            style: _nameActionStyle,
                            onPressed: savingName ? null : _saveName,
                            child: Text(savingName ? 'Saving…' : 'Save'),
                          ),
                          const SizedBox(width: 16),
                          TextButton(
                            style: _nameActionStyle,
                            onPressed: savingName
                                ? null
                                : () {
                                    FocusScope.of(context).unfocus();
                                    setState(() => editingName = false);
                                  },
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    height: 48,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            profile.name,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 24,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 24,
                    child: TextButton.icon(
                      onPressed: loading ? null : _editName,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit name'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
