import 'dart:collection';

/// FIFO buffer that only keeps items from the last [window] of time.
///
/// Items must be added in chronological order. Eviction is driven by the
/// timestamp of the newest item, so the buffer works with simulated clocks.
class TimeWindowBuffer<T> {
  TimeWindowBuffer({
    required Duration window,
    required DateTime Function(T item) timeOf,
  }) : _window = window,
       _timeOf = timeOf;

  final DateTime Function(T item) _timeOf;
  final ListQueue<T> _items = ListQueue<T>();
  Duration _window;

  Duration get window => _window;

  set window(Duration value) {
    _window = value;
    if (_items.isNotEmpty) _evict(_timeOf(_items.last));
  }

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  Iterable<T> get items => _items;
  T? get first => _items.isEmpty ? null : _items.first;
  T? get last => _items.isEmpty ? null : _items.last;

  /// Time covered by the buffered items (never longer than [window]).
  Duration get span => _items.length < 2
      ? Duration.zero
      : _timeOf(_items.last).difference(_timeOf(_items.first));

  void add(T item) {
    final time = _timeOf(item);
    if (_items.isNotEmpty && time.isBefore(_timeOf(_items.last))) {
      throw StateError('Items must be added in chronological order');
    }
    _items.addLast(item);
    _evict(time);
  }

  void clear() => _items.clear();

  void _evict(DateTime newest) {
    final cutoff = newest.subtract(_window);
    while (_items.isNotEmpty && _timeOf(_items.first).isBefore(cutoff)) {
      _items.removeFirst();
    }
  }
}
