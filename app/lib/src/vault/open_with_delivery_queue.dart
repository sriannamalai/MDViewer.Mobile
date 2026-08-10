import 'open_with_channel.dart';

/// The retry/queueing policy behind `main.dart`'s open-with cold-start
/// delivery: a file that arrives before the root `Navigator` is mounted (a
/// cold "Open with" launch racing the very first frame) isn't dropped —
/// it's queued, and [drain] is asked to try again on a later frame, up to
/// [maxAttempts] times before giving up (a permanently-unmounted Navigator
/// should never happen in practice; this bound is a safety net against an
/// infinite retry loop, not an expected path).
///
/// Deliberately has no Flutter/`WidgetsBinding` dependency of its own —
/// [drain]'s `isReady`/`scheduleRetry` callbacks are how `main.dart`
/// supplies the real "is the Navigator mounted yet" check and "try again
/// next frame" mechanism (`addPostFrameCallback` + `scheduleFrame`). That
/// makes the policy itself (queue growth, drain-on-ready, give-up-after-N,
/// no duplicate retry chains from re-entrant calls) unit-testable without
/// pumping real frames — see `open_with_delivery_queue_test.dart`.
class OpenWithDeliveryQueue {
  OpenWithDeliveryQueue({this.maxAttempts = 10});

  final int maxAttempts;

  final List<OpenWithFile> _pending = [];
  int _attempts = 0;
  bool _retryScheduled = false;

  /// Read-only snapshot of what's still queued — a test seam, and useful
  /// for the (rare) case something wants to know delivery hasn't landed
  /// yet.
  List<OpenWithFile> get pending => List.unmodifiable(_pending);

  void add(OpenWithFile file) => _pending.add(file);

  /// Attempts to hand every queued file to [deliver]. If [isReady]()
  /// (evaluated fresh — not cached from an earlier call, since readiness
  /// can change between attempts) is true, delivers everything queued and
  /// clears the queue. Otherwise schedules exactly one retry via
  /// [scheduleRetry] (re-entrant calls made while a retry is already
  /// pending just let that retry pick up anything newly [add]ed, rather
  /// than stacking up parallel retry chains) — unless [maxAttempts] has
  /// already been spent, in which case the queue is dropped.
  void drain({
    required bool Function() isReady,
    required void Function(OpenWithFile file) deliver,
    required void Function(void Function() retry) scheduleRetry,
  }) {
    if (_pending.isEmpty) return;

    if (isReady()) {
      _attempts = 0;
      _retryScheduled = false;
      final queued = List<OpenWithFile>.of(_pending);
      _pending.clear();
      for (final file in queued) {
        deliver(file);
      }
      return;
    }

    if (_retryScheduled) return;

    _attempts++;
    if (_attempts > maxAttempts) {
      _pending.clear();
      _attempts = 0;
      return;
    }

    _retryScheduled = true;
    scheduleRetry(() {
      _retryScheduled = false;
      drain(isReady: isReady, deliver: deliver, scheduleRetry: scheduleRetry);
    });
  }
}
