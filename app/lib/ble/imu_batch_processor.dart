import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/imu_packet.dart';

typedef ImuBatchProcessorFactory = ImuBatchProcessor Function(DeviceInfo info);

/// Parsed IMU batch with both raw samples and physical-unit readings.
class ProcessedImuBatch {
  const ProcessedImuBatch({
    required this.samples,
    required this.readings,
    required this.newGaps,
  });

  final List<ImuSample> samples;
  final List<ImuReading> readings;
  final int newGaps;
}

/// Stateful per-stream processor. Implementations own their sequence tracker.
abstract interface class ImuBatchProcessor {
  FutureOr<ProcessedImuBatch> parse(List<int> bytes);

  Future<void> dispose();
}

/// Synchronous implementation used by unit tests and lightweight fakes.
class SyncImuBatchProcessor implements ImuBatchProcessor {
  SyncImuBatchProcessor(this._info);

  final DeviceInfo _info;
  final ImuSeqTracker _tracker = ImuSeqTracker();

  @override
  ProcessedImuBatch parse(List<int> bytes) {
    return _processImuBatch(bytes, _tracker, _info);
  }

  @override
  Future<void> dispose() async {}
}

/// Long-lived isolate processor for live app streams.
///
/// Creating an isolate per packet is too expensive; this keeps one worker per
/// wheel stream and sends batches through it in order.
class IsolateImuBatchProcessor implements ImuBatchProcessor {
  IsolateImuBatchProcessor(this._info);

  final DeviceInfo _info;
  final Completer<SendPort> _ready = Completer<SendPort>();
  final Map<int, Completer<ProcessedImuBatch>> _pending =
      <int, Completer<ProcessedImuBatch>>{};

  Isolate? _isolate;
  ReceivePort? _receivePort;
  Future<void>? _startFuture;
  var _nextRequestId = 0;
  var _disposed = false;

  @override
  Future<ProcessedImuBatch> parse(List<int> bytes) async {
    if (_disposed) {
      throw StateError('IMU batch processor has been disposed');
    }
    await _ensureStarted();
    if (_disposed) {
      throw StateError('IMU batch processor has been disposed');
    }

    final id = _nextRequestId++;
    final completer = Completer<ProcessedImuBatch>();
    _pending[id] = completer;
    final sendPort = await _ready.future;
    sendPort.send(_WorkerParseRequest(id, Uint8List.fromList(bytes)));
    return completer.future;
  }

  Future<void> _ensureStarted() {
    return _startFuture ??= _start();
  }

  Future<void> _start() async {
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    receivePort.listen(_handleWorkerMessage);
    _isolate = await Isolate.spawn(
      _imuBatchProcessorEntry,
      _WorkerInit(receivePort.sendPort, _info),
    );
    await _ready.future;
  }

  void _handleWorkerMessage(Object? message) {
    if (message is SendPort) {
      if (!_ready.isCompleted) {
        _ready.complete(message);
      }
      return;
    }

    if (message is! _WorkerParseResponse) {
      return;
    }

    final completer = _pending.remove(message.id);
    if (completer == null || completer.isCompleted) {
      return;
    }

    final result = message.result;
    if (result != null) {
      completer.complete(result);
      return;
    }

    completer.completeError(
      StateError(message.error ?? 'IMU parser worker failed'),
      StackTrace.fromString(message.stackTrace ?? ''),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_ready.isCompleted) {
      final sendPort = await _ready.future;
      sendPort.send(const _WorkerDisposeRequest());
    }
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('IMU batch processor disposed'));
      }
    }
    _pending.clear();
  }
}

ProcessedImuBatch _processImuBatch(
  List<int> bytes,
  ImuSeqTracker tracker,
  DeviceInfo info,
) {
  final result = ImuPacketParser.parseBatchWithGaps(bytes, tracker);
  final readings = result.samples
      .map((sample) => sample.toReading(info))
      .toList(growable: false);
  return ProcessedImuBatch(
    samples: result.samples,
    readings: readings,
    newGaps: result.newGaps,
  );
}

void _imuBatchProcessorEntry(_WorkerInit init) {
  final receivePort = ReceivePort();
  final tracker = ImuSeqTracker();
  init.replyPort.send(receivePort.sendPort);

  receivePort.listen((Object? message) {
    if (message is _WorkerDisposeRequest) {
      receivePort.close();
      return;
    }
    if (message is! _WorkerParseRequest) {
      return;
    }

    try {
      final result = _processImuBatch(message.bytes, tracker, init.info);
      init.replyPort.send(_WorkerParseResponse.success(message.id, result));
    } on Object catch (e, st) {
      init.replyPort.send(
        _WorkerParseResponse.failure(message.id, e.toString(), st.toString()),
      );
    }
  });
}

class _WorkerInit {
  const _WorkerInit(this.replyPort, this.info);

  final SendPort replyPort;
  final DeviceInfo info;
}

class _WorkerParseRequest {
  const _WorkerParseRequest(this.id, this.bytes);

  final int id;
  final Uint8List bytes;
}

class _WorkerParseResponse {
  const _WorkerParseResponse.success(this.id, this.result)
    : error = null,
      stackTrace = null;

  const _WorkerParseResponse.failure(this.id, this.error, this.stackTrace)
    : result = null;

  final int id;
  final ProcessedImuBatch? result;
  final String? error;
  final String? stackTrace;
}

class _WorkerDisposeRequest {
  const _WorkerDisposeRequest();
}
