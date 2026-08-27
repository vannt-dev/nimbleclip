import 'dart:async';
import 'dart:collection';

class AsyncWorkQueue<T> {
  AsyncWorkQueue({
    required this.worker,
    bool Function(T item)? shouldRun,
    int maxConcurrent = 3,
  }) : _shouldRun = shouldRun ?? ((_) => true),
       _maxConcurrent = maxConcurrent.clamp(1, 5).toInt();

  final Future<void> Function(T item) worker;
  final bool Function(T item) _shouldRun;

  /// A queue rather than a list: draining took the head with `removeAt(0)`,
  /// which shifts every remaining element down on each dequeue.
  final Queue<T> _pending = Queue<T>();
  int _running = 0;
  int _maxConcurrent;

  int get maxConcurrent => _maxConcurrent;
  int get running => _running;
  int get pending => _pending.length;

  set maxConcurrent(int value) {
    _maxConcurrent = value.clamp(1, 5).toInt();
    _drain();
  }

  void add(T item) {
    _pending.add(item);
    _drain();
  }

  void removeWhere(bool Function(T item) predicate) {
    _pending.removeWhere(predicate);
  }

  void clear() => _pending.clear();

  void _drain() {
    while (_running < _maxConcurrent && _pending.isNotEmpty) {
      final item = _pending.removeFirst();
      if (!_shouldRun(item)) continue;
      _running++;
      unawaited(
        worker(item).whenComplete(() {
          _running--;
          _drain();
        }),
      );
    }
  }
}
