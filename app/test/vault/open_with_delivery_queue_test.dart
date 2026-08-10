// OpenWithDeliveryQueue unit tests (task-7 review, Minor finding 3): the
// cold-start open-with retry/queueing policy, tested without pumping real
// frames — `scheduleRetry` is a fake that just captures the callback so the
// test can invoke it manually to simulate "the next frame happened".

import 'dart:typed_data';

import 'package:app/src/vault/open_with_channel.dart';
import 'package:app/src/vault/open_with_delivery_queue.dart';
import 'package:flutter_test/flutter_test.dart';

OpenWithFile _file(String name) =>
    OpenWithFile(name: name, bytes: Uint8List.fromList([1, 2, 3]));

void main() {
  group('OpenWithDeliveryQueue.drain', () {
    test('delivers immediately when isReady() is already true', () {
      final queue = OpenWithDeliveryQueue();
      final delivered = <OpenWithFile>[];
      queue.add(_file('A.md'));

      queue.drain(
        isReady: () => true,
        deliver: delivered.add,
        scheduleRetry: (_) => fail('should not need a retry'),
      );

      expect(delivered.map((f) => f.name), ['A.md']);
      expect(queue.pending, isEmpty);
    });

    test(
      'queues and schedules a retry when the Navigator is not ready yet',
      () {
        final queue = OpenWithDeliveryQueue();
        final delivered = <OpenWithFile>[];
        final retries = <void Function()>[];
        queue.add(_file('A.md'));

        queue.drain(
          isReady: () => false,
          deliver: delivered.add,
          scheduleRetry: retries.add,
        );

        expect(delivered, isEmpty);
        expect(queue.pending.map((f) => f.name), ['A.md']);
        expect(retries, hasLength(1));
      },
    );

    test('delivers once a later retry finds the Navigator ready', () {
      final queue = OpenWithDeliveryQueue();
      final delivered = <OpenWithFile>[];
      final retries = <void Function()>[];
      var ready = false;
      queue.add(_file('A.md'));

      queue.drain(
        isReady: () => ready,
        deliver: delivered.add,
        scheduleRetry: retries.add,
      );
      expect(delivered, isEmpty);

      ready = true;
      retries.removeAt(0)(); // simulate "the next frame happened"

      expect(delivered.map((f) => f.name), ['A.md']);
      expect(queue.pending, isEmpty);
    });

    test(
      'a file added while a retry is already pending is delivered by that same retry',
      () {
        final queue = OpenWithDeliveryQueue();
        final delivered = <OpenWithFile>[];
        final retries = <void Function()>[];
        var ready = false;
        queue.add(_file('A.md'));

        queue.drain(
          isReady: () => ready,
          deliver: delivered.add,
          scheduleRetry: retries.add,
        );
        expect(retries, hasLength(1));

        // A second file arrives before the first retry has fired — this
        // must NOT schedule a second, parallel retry chain.
        queue.add(_file('B.md'));
        queue.drain(
          isReady: () => ready,
          deliver: delivered.add,
          scheduleRetry: retries.add,
        );
        expect(
          retries,
          hasLength(1),
          reason:
              'a retry is already pending; re-entrant drain() calls '
              'must not stack up additional retry chains',
        );

        ready = true;
        retries.single();

        expect(delivered.map((f) => f.name), ['A.md', 'B.md']);
      },
    );

    test('gives up after maxAttempts retries, dropping the queue', () {
      final queue = OpenWithDeliveryQueue(maxAttempts: 3);
      final delivered = <OpenWithFile>[];
      final retries = <void Function()>[];
      queue.add(_file('A.md'));

      void fireLatestRetry() {
        final retry = retries.removeLast();
        retry();
      }

      queue.drain(
        isReady: () => false,
        deliver: delivered.add,
        scheduleRetry: retries.add,
      );
      fireLatestRetry(); // attempt 2
      fireLatestRetry(); // attempt 3
      fireLatestRetry(); // attempt 4 -> exceeds maxAttempts(3), gives up

      expect(delivered, isEmpty);
      expect(queue.pending, isEmpty);
      expect(
        retries,
        isEmpty,
        reason: 'no further retry should be scheduled once given up',
      );
    });

    test('a queue with nothing pending is a no-op', () {
      final queue = OpenWithDeliveryQueue();
      queue.drain(
        isReady: () => false,
        deliver: (_) => fail('nothing to deliver'),
        scheduleRetry: (_) => fail('nothing to retry'),
      );
    });
  });
}
