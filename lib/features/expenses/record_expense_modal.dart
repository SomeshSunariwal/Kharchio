import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/ai/model_manager.dart';
import '../../services/ai/native_ai.dart';
import '../../services/audio/voice_capture.dart';
import '../../services/ai/expense_extractor.dart';
import '../../services/audio/live_transcription_queue.dart';

import '../../core/theme.dart';
import '../../core/preferences.dart';
import '../../core/categories.dart';
import '../../shared/app_notification.dart';
import 'add_expense_screen.dart';
import 'widgets/recording_waveform.dart';
import 'widgets/recording_transcript.dart';
import 'widgets/recording_summary_list.dart';

enum RecordingStage {
  initializing,
  recording,
  paused,
  processing,
  review,
  failed,
}

class RecordExpenseModal extends ConsumerStatefulWidget {
  const RecordExpenseModal({super.key});
  @override
  ConsumerState<RecordExpenseModal> createState() => _RecordState();
}

class _RecordState extends ConsumerState<RecordExpenseModal>
    with WidgetsBindingObserver {
  final text = TextEditingController();
  final transcriptScroll = ScrollController();
  final summaryScroll = ScrollController();
  final capture = VoiceCapture();
  final elapsed = Stopwatch();
  Timer? timer;
  late final liveTranscriptions = LiveTranscriptionQueue(transcribeLive);
  Future<void>? get liveWork => liveTranscriptions.work;
  Future<void>? whisperWarmWork;
  NativeAiJob? warmJob;
  Object? warmFailure;
  bool speechModelReady = false;
  NativeAiJob? liveJob;
  List<ExtractedExpense> summary = [];
  int transcribedBytes = 0;
  NativeAiJob? job;
  RecordingStage stage = RecordingStage.initializing;
  final seconds = ValueNotifier<int>(0);
  String? error;
  String processingLabel = 'Preparing offline models…';
  bool changingControls = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    capture.onAudio = () {
      if (mounted && stage == RecordingStage.paused) {
        unawaited(liveTranscriptions.request(flush: true));
      }
    };
    Future.microtask(startRecording);
  }

  Future<void> startRecording() async {
    if (!mounted) return;
    setState(() {
      stage = RecordingStage.initializing;
      error = null;
      text.clear();
      summary = [];
      transcribedBytes = 0;
      warmFailure = null;
      speechModelReady = false;
    });
    try {
      final models = await ref
          .read(offlineModelsProvider.notifier)
          .requireAvailable(
            speechMode: ref
                .read(preferencesProvider)
                .speechProcessing
                .nativeValue,
          );
      if (!mounted) return;
      await NativeAiJob.setProcessing(
        mode: ref.read(preferencesProvider).speechProcessing.nativeValue,
      );
      if (!mounted) return;
      await capture.start();
      if (!mounted) return;
      elapsed.reset();
      elapsed.start();
      setState(() {
        seconds.value = 0;
        stage = RecordingStage.recording;
      });
      whisperWarmWork = prepareWhisperModel(models.whisper);
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || stage != RecordingStage.recording) return;
        seconds.value = elapsed.elapsed.inSeconds;
        if (seconds.value >= 90) {
          unawaited(process());
        } else if (seconds.value % 3 == 0 && liveWork == null) {
          unawaited(liveTranscriptions.request());
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          stage = RecordingStage.failed;
          error = _errorMessage(e);
        });
      }
    }
  }

  Future<void> prepareWhisperModel(String path) async {
    final current = NativeAiJob();
    warmJob = current;
    try {
      await current.prepareWhisper(path);
      if (mounted) setState(() => speechModelReady = true);
    } catch (e) {
      warmFailure = e;
      if (mounted && stage != RecordingStage.processing) {
        timer?.cancel();
        elapsed.stop();
        try {
          await capture.stop();
        } catch (_) {
          // Preserve the original model-loading error during microphone cleanup.
        }
        capture.clearAudio();
        if (mounted) {
          setState(() {
            stage = RecordingStage.failed;
            error = _errorMessage(e);
          });
        }
      }
    } finally {
      current.dispose();
      if (identical(warmJob, current)) warmJob = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        stage == RecordingStage.recording) {
      unawaited(toggle());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    capture.onAudio = null;
    liveTranscriptions.cancelPending();
    job?.cancel();
    liveJob?.cancel();
    warmJob?.cancel();
    timer?.cancel();
    elapsed.stop();
    seconds.dispose();
    text.dispose();
    transcriptScroll.dispose();
    summaryScroll.dispose();
    unawaited(capture.dispose());
    unawaited(
      NativeAiJob.releaseModels().catchError((Object e) {
        if (kDebugMode) debugPrint('KharchioAI: model cleanup failed: $e');
      }),
    );
    super.dispose();
  }

  Future<void> toggle() async {
    if (changingControls ||
        (stage != RecordingStage.recording && stage != RecordingStage.paused)) {
      return;
    }
    changingControls = true;
    try {
      final resume = stage == RecordingStage.paused;
      if (resume) {
        await capture.resume();
        elapsed.start();
      } else {
        await capture.pause();
        elapsed.stop();
      }
      if (!mounted) return;
      setState(
        () => stage = resume ? RecordingStage.recording : RecordingStage.paused,
      );
      if (!resume) {
        // Pause capture only. Finish every sample already buffered, even if
        // model warm-up or an older preview is still in progress.
        unawaited(liveTranscriptions.request(flush: true));
      }
    } catch (e) {
      if (mounted) setState(() => error = _errorMessage(e));
    } finally {
      changingControls = false;
    }
  }

  Future<void> transcribeLive(bool flush) async {
    await whisperWarmWork;
    if (!mounted ||
        (stage != RecordingStage.recording && stage != RecordingStage.paused) ||
        !speechModelReady ||
        capture.length < (flush ? 3200 : 32000)) {
      return;
    }
    final bytes = capture.snapshot();
    if (bytes.length <= transcribedBytes) return;
    final current = NativeAiJob();
    liveJob = current;
    try {
      final models = await ref.read(offlineModelsProvider.future);
      final language = ref.read(preferencesProvider).speechLanguage;
      final recognized = await current.transcribe(
        models.whisper,
        bytes,
        language,
      );
      if (mounted && stage != RecordingStage.failed) {
        transcribedBytes = bytes.length;
        setState(() {
          text.text = recognized;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && stage == RecordingStage.paused) {
        setState(() => error = _errorMessage(e));
      }
      // Stop performs a final transcription and exposes actionable errors.
    } finally {
      current.dispose();
      if (identical(liveJob, current)) liveJob = null;
    }
  }

  void createCards() {
    if (stage != RecordingStage.review || summary.isEmpty) return;
    final values = [
      for (var i = 0; i < summary.length; i++)
        ExpenseDraft(
          id: '${DateTime.now().microsecondsSinceEpoch}-$i',
          title: summary[i].title,
          description: summary[i].description,
          category: summary[i].category,
          amount: summary[i].amount.toStringAsFixed(2),
        ),
    ];
    Navigator.pop(context, values);
  }

  Future<void> process() async {
    if ((stage != RecordingStage.recording && stage != RecordingStage.paused) ||
        changingControls) {
      return;
    }
    final processingTime = Stopwatch()..start();
    elapsed.stop();
    timer?.cancel();
    setState(() {
      stage = RecordingStage.processing;
      error = null;
      processingLabel = 'Transcribing on this device…';
    });
    final currentJob = NativeAiJob();
    job = currentJob;
    try {
      final models = await ref.read(offlineModelsProvider.future);
      final audio = await capture.stop();
      await whisperWarmWork;
      if (warmFailure != null) throw StateError(_errorMessage(warmFailure!));
      // Do not finish an obsolete preview before starting the final decode.
      liveTranscriptions.cancelPending();
      liveJob?.cancel();
      await liveWork;
      if (!mounted) return;
      await ref
          .read(offlineModelsProvider.notifier)
          .requireAvailable(expense: true);
      if (!mounted) return;
      final transcriptionTime = Stopwatch()..start();
      final language = ref.read(preferencesProvider).speechLanguage;
      final transcript =
          audio.length == transcribedBytes && text.text.trim().isNotEmpty
          ? text.text.trim()
          : await currentJob.transcribe(models.whisper, audio, language);
      if (kDebugMode) {
        debugPrint(
          'KharchioAI: final transcription ${transcriptionTime.elapsedMilliseconds} ms',
        );
      }
      capture.clearAudio();
      if (!mounted) return;
      text.text = transcript;
      setState(() => processingLabel = 'Loading the expense model…');
      await NativeAiJob.setProcessing(
        mode: ref.read(preferencesProvider).expenseProcessing.nativeValue,
      );
      if (!mounted) return;
      await currentJob.prepareQwen(models.qwen);
      if (!mounted) return;
      setState(() => processingLabel = 'Extracting expense details with Qwen…');
      final result = await ExpenseExtractor().extract(
        job: currentJob,
        model: models.qwen,
        text: transcript,
        categories: context.categoryNames,
        currency: context.currency.code,
        onValidated: (duration) {
          if (kDebugMode) {
            debugPrint(
              'KharchioAI: JSON validation ${duration.inMicroseconds} us',
            );
          }
        },
      );
      if (!mounted) return;
      setState(() {
        summary = result;
        stage = RecordingStage.review;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && stage == RecordingStage.review && kDebugMode) {
          debugPrint(
            'KharchioAI: summary visible ${processingTime.elapsedMilliseconds} ms after Stop',
          );
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          stage = RecordingStage.failed;
          error = _errorMessage(e);
        });
      }
    } finally {
      capture.clearAudio();
      currentJob.dispose();
      if (identical(job, currentJob)) job = null;
      await NativeAiJob.releaseModels();
    }
  }

  @override
  Widget build(BuildContext context) {
    final processing =
        stage == RecordingStage.processing ||
        stage == RecordingStage.initializing;
    final expanded = stage == RecordingStage.review;
    final colors = context.appColors;
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          height: expanded ? MediaQuery.sizeOf(context).height * .94 : null,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Record Expense',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Speak what you spent on. Review the summary, then create expense cards.',
                style: TextStyle(fontSize: 12, color: colors.muted),
              ),
              const SizedBox(height: 10),
              RecordingTranscript(
                text: text,
                scroll: transcriptScroll,
                preparing:
                    stage == RecordingStage.recording && !speechModelReady,
              ),
              const SizedBox(height: 10),
              if (processing)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: _box(),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: red,
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          processingLabel,
                          style: const TextStyle(fontSize: 12, color: red),
                        ),
                      ),
                    ],
                  ),
                )
              else if (stage == RecordingStage.recording ||
                  stage == RecordingStage.paused) ...[
                Container(
                  height: 68,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: _box(),
                  child: Row(
                    children: [
                      Expanded(
                        child: RecordingWaveform(
                          active: stage == RecordingStage.recording,
                          level: capture.level,
                        ),
                      ),
                      IconButton.filled(
                        tooltip: stage == RecordingStage.paused
                            ? 'Resume recording'
                            : 'Pause recording',
                        onPressed: toggle,
                        style: IconButton.styleFrom(
                          backgroundColor: red.withValues(alpha: .12),
                          foregroundColor: red,
                        ),
                        icon: Icon(
                          stage == RecordingStage.paused
                              ? Icons.play_arrow
                              : Icons.pause,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        tooltip: 'Stop and process recording',
                        onPressed: process,
                        style: IconButton.styleFrom(
                          backgroundColor: red,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.stop_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                ValueListenableBuilder<int>(
                  valueListenable: seconds,
                  builder: (context, value, _) => Text(
                    '${stage == RecordingStage.paused ? 'Paused' : 'Recording'} · ${_time(value)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: red, fontSize: 12),
                  ),
                ),
              ],
              if (stage == RecordingStage.review) ...[
                Text(
                  'Expense summary (${summary.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Expanded(
                  child: RecordingSummaryList(
                    expenses: summary,
                    scroll: summaryScroll,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: createCards,
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: Text('Create Expense Cards (${summary.length})'),
                  ),
                ),
              ] else ...[
                if (error != null) ...[
                  AppNotificationCard(message: error!, isError: true),
                  const SizedBox(height: 10),
                ],
                if (stage == RecordingStage.failed)
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton.icon(
                      onPressed: startRecording,
                      icon: const Icon(Icons.mic_rounded),
                      label: const Text('Record again'),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  'Offline processing · Audio is never saved',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: colors.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _errorMessage(Object error) => error is StateError
      ? error.message
      : error is FormatException
      ? error.message
      : error.toString();

  String _time(int value) =>
      '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
  BoxDecoration _box() => BoxDecoration(
    color: red.withValues(alpha: .045),
    border: Border.all(color: red.withValues(alpha: .22)),
    borderRadius: BorderRadius.circular(14),
  );
}
