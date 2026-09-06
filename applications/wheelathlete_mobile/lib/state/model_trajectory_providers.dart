import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/model/on_device_trajectory_model.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/preview_providers.dart';

final trajectoryModelClientProvider = Provider<TrajectoryModelClient>((ref) {
  final client = OnDeviceTrajectoryModelClient();
  ref.onDispose(client.dispose);
  return client;
});

class ModelTrajectoryState {
  const ModelTrajectoryState({
    this.isRunning = false,
    this.result,
    this.preprocess,
    this.error,
  });

  final bool isRunning;
  final TrajectoryResult? result;
  final TrajectoryPreprocessResult? preprocess;
  final String? error;

  ModelTrajectoryState copyWith({
    bool? isRunning,
    Object? result = _unset,
    Object? preprocess = _unset,
    Object? error = _unset,
  }) => ModelTrajectoryState(
    isRunning: isRunning ?? this.isRunning,
    result: identical(result, _unset)
        ? this.result
        : result as TrajectoryResult?,
    preprocess: identical(preprocess, _unset)
        ? this.preprocess
        : preprocess as TrajectoryPreprocessResult?,
    error: identical(error, _unset) ? this.error : error as String?,
  );

  static const _unset = Object();
}

class ModelTrajectoryNotifier extends Notifier<ModelTrajectoryState> {
  ModelTrajectoryNotifier(this.source);

  final PreviewSource source;
  var _generation = 0;

  @override
  ModelTrajectoryState build() => const ModelTrajectoryState();

  Future<void> generate(SessionMeta meta) async {
    if (state.isRunning) return;
    final generation = ++_generation;
    state = state.copyWith(isRunning: true, error: null);
    try {
      final samples = await _loadAllSamples();
      if (!ref.mounted || generation != _generation) return;
      final input = prepareTrajectoryInput(
        samples,
        sourceRateHz: meta.sampleRateHz,
      );
      final result = await ref
          .read(trajectoryModelClientProvider)
          .infer(meta: meta, input: input);
      if (!ref.mounted || generation != _generation) return;
      state = ModelTrajectoryState(result: result, preprocess: input);
    } on Object catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = ModelTrajectoryState(error: error.toString());
    }
  }

  void clear() {
    _generation++;
    state = const ModelTrajectoryState();
  }

  Future<List<BufferedSample>> _loadAllSamples() async {
    switch (source) {
      case InMemoryPreviewSource(:final samples):
        return List<BufferedSample>.unmodifiable(samples);
      case DiskPreviewSource(
        :final topic,
        :final trialNumber,
        :final sessionId,
      ):
        return ref
            .read(storageRepositoryProvider)
            .readSamples(topic, trialNumber, sessionId);
    }
  }
}

final modelTrajectoryProvider =
    NotifierProvider.family<
      ModelTrajectoryNotifier,
      ModelTrajectoryState,
      PreviewSource
    >(ModelTrajectoryNotifier.new);
