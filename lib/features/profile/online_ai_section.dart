import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/preferences.dart';
import '../../core/theme.dart';
import '../../services/ai/online_ai_settings.dart';
import '../../services/ai/online_ai_client.dart';
import '../../shared/app_dropdown.dart';
import '../../shared/preference_dropdown_row.dart';
import '../../shared/widgets.dart';
import 'online_api_key_dialog.dart';

class OnlineAiSection extends ConsumerStatefulWidget {
  const OnlineAiSection({super.key});
  @override
  ConsumerState<OnlineAiSection> createState() => _OnlineAiSectionState();
}

class _OnlineAiSectionState extends ConsumerState<OnlineAiSection> {
  bool changingModel = false;
  OnlineAiClient? checkingClient;
  @override
  void dispose() {
    checkingClient?.close();
    super.dispose();
  }

  Future<void> _selectModel(
    OnlineAiProvider provider,
    OnlineAiModels models,
    String value, {
    bool speech = false,
  }) async {
    if (changingModel ||
        value == (speech ? models.speechSelection : models.selection)) {
      return;
    }
    setState(() => changingModel = true);
    try {
      final keys = ref.read(onlineAiKeysProvider);
      final key = await keys.read(provider);
      if (!mounted || key == null) return;
      final selected = speech
          ? models.selectSpeech(value)
          : models.selectExpense(value);
      checkingClient = ref.read(onlineAiClientFactoryProvider)(provider, key);
      await checkingClient!.checkSelectedModels(selected, previous: models);
      if (!mounted) return;
      await keys.save(provider, key, validated: true, models: selected);
      ref.invalidate(onlineAiReadyProvider(provider));
      if (mounted) notice(context, 'Model is ready.');
    } catch (error) {
      if (mounted) {
        notice(
          context,
          error is OnlineAiConnectionException ? error.message : 'Could not select this model. Your previous model is still selected.',
          isError: true,
        );
      }
    } finally {
      checkingClient?.close();
      checkingClient = null;
      if (mounted) setState(() => changingModel = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(preferencesProvider).onlineAiProvider;
    final hasProvider = provider != OnlineAiProvider.none;
    final ready =
        hasProvider && ref.watch(onlineAiReadyProvider(provider)).value == true;
    final keyState = hasProvider
        ? ref.watch(onlineAiHasKeyProvider(provider))
        : const AsyncData(false);
    final models = ready
        ? ref.watch(onlineAiModelsProvider(provider)).value
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Online AI',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Column(
            children: [
              PreferenceDropdownRow<OnlineAiProvider>(
                value: provider,
                label: 'Provider',
                description: provider == OnlineAiProvider.claude
                    ? 'Whisper on device · Claude expenses'
                    : provider == OnlineAiProvider.openrouter
                    ? 'Audio chunks · Auto prefers free models'
                    : null,
                enabled: !changingModel,
                icon: Icons.cloud_outlined,
                options: [
                  for (final value in OnlineAiProvider.values)
                    AppDropdownOption(
                      value,
                      value.label,
                      icon: switch (value) {
                        OnlineAiProvider.none => Icons.block_outlined,
                        OnlineAiProvider.gemini => Icons.auto_awesome_outlined,
                        OnlineAiProvider.openai => Icons.psychology_outlined,
                        OnlineAiProvider.claude => Icons.chat_bubble_outline,
                        OnlineAiProvider.openrouter => Icons.hub_outlined,
                      },
                    ),
                ],
                onChanged: (value) async {
                  try {
                    await ref
                        .read(preferencesProvider.notifier)
                        .setOnlineAiProvider(value);
                  } catch (_) {
                    if (context.mounted) {
                      notice(
                        context,
                        'Could not save the provider. Please try again.',
                        isError: true,
                      );
                    }
                  }
                },
              ),
              Divider(height: 1, color: context.appColors.line),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 54),
                child: Row(
                  children: [
                    Icon(
                      Icons.key_outlined,
                      size: 16,
                      color: hasProvider ? green : context.appColors.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'API Key',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            !hasProvider
                                ? 'Select a provider first'
                                : keyState.isLoading
                                ? 'Checking saved key…'
                                : keyState.hasError
                                ? 'Could not read saved key'
                                : keyState.value == true
                                ? 'Key saved securely on this device'
                                : 'Use your own ${provider.label} key',
                            style: TextStyle(
                              fontSize: 10,
                              color: context.appColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (ready) ...[
                      const Text(
                        'Ready',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: green,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(56, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        side: BorderSide(color: context.appColors.line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onPressed:
                          !hasProvider || keyState.isLoading || changingModel
                          ? null
                          : () => showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) =>
                                  OnlineApiKeyDialog(provider: provider),
                            ),
                      child: Text(
                        keyState.value == true ? 'Edit Key' : 'Add Key',
                      ),
                    ),
                  ],
                ),
              ),
              if (ready && models != null) ...[
                Divider(height: 1, color: context.appColors.line),
                PreferenceDropdownRow<String>(
                  label: 'Speech Model',
                  icon: Icons.graphic_eq,
                  value: models.liveSpeech
                      ? models.speechSelection
                      : OnlineAiModels.onDeviceSpeech,
                  enabled: !changingModel && models.liveSpeech,
                  descriptionError: !models.liveSpeech,
                  description: !models.liveSpeech
                      ? 'Using on-device Whisper'
                      : models.speech,
                  options: [
                    if (!models.liveSpeech)
                      const AppDropdownOption(
                        OnlineAiModels.onDeviceSpeech,
                        'Whisper (on device)',
                        icon: Icons.mic_outlined,
                      )
                    else ...[
                      const AppDropdownOption(
                        'auto',
                        'Auto',
                        icon: Icons.auto_awesome_outlined,
                      ),
                      for (final name in _freeFirstModels(
                        provider,
                        models.availableSpeech,
                        speech: true,
                        freeModels: models.freeModels,
                      ))
                        _modelOption(
                          provider,
                          name,
                          speech: true,
                          freeModels: models.freeModels,
                        ),
                    ],
                  ],
                  onChanged: (value) =>
                      _selectModel(provider, models, value, speech: true),
                ),
                Divider(height: 1, color: context.appColors.line),
                PreferenceDropdownRow<String>(
                  label: 'Available Model',
                  icon: Icons.auto_awesome_outlined,
                  value: models.selection,
                  description: models.expense,
                  enabled: !changingModel,
                  options: [
                    const AppDropdownOption(
                      'auto',
                      'Auto',
                      icon: Icons.auto_awesome_outlined,
                    ),
                    for (final name in _freeFirstModels(
                      provider,
                      models.available,
                      freeModels: models.freeModels,
                    ))
                      _modelOption(
                        provider,
                        name,
                        freeModels: models.freeModels,
                      ),
                  ],
                  onChanged: (value) => _selectModel(provider, models, value),
                ),
                if (changingModel) const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  bool _isFreeModel(
    OnlineAiProvider provider,
    String model, {
    bool speech = false,
    List<String> freeModels = const [],
  }) => provider == OnlineAiProvider.openrouter
      ? freeModels.contains(model)
      : provider == OnlineAiProvider.gemini &&
            (speech
                ? OnlineAiClient.freeTierGeminiLiveModels.contains(model)
                : OnlineAiClient.freeTierGeminiModels.contains(model));

  Iterable<String> _freeFirstModels(
    OnlineAiProvider provider,
    List<String> names, {
    bool speech = false,
    List<String> freeModels = const [],
  }) sync* {
    final unique = names.toSet();
    bool free(String name) =>
        _isFreeModel(provider, name, speech: speech, freeModels: freeModels);
    yield* unique.where(free);
    yield* unique.where((name) => !free(name));
  }

  AppDropdownOption<String> _modelOption(
    OnlineAiProvider provider,
    String model, {
    bool speech = false,
    List<String> freeModels = const [],
  }) {
    final free = _isFreeModel(
      provider,
      model,
      speech: speech,
      freeModels: freeModels,
    );
    return AppDropdownOption(
      model,
      model,
      badge: free ? '[free]' : '[paid]',
      badgeColor: free ? green : red,
    );
  }
}
