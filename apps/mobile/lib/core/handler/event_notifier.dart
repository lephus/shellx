import 'dart:async';

import 'package:flutter/foundation.dart';

enum EventPriority {
  low(0),
  normal(50),
  high(100)
  ;

  final int value;
  const EventPriority(this.value);
}

class _ListenerEntry<T> {
  final FutureOr Function(T) callback;
  final EventPriority priority;

  _ListenerEntry(this.callback, this.priority);
}

class EventNotifier<T> {
  final Map<String, _ListenerEntry<T>> _listeners = {};

  void notifyAll(T data) {
    final sortedEntries = _listeners.entries.toList()
      ..sort(
        (a, b) => b.value.priority.value.compareTo(a.value.priority.value),
      );

    for (var entry in sortedEntries) {
      notify(key: entry.key, data: data);
    }
  }

  FutureOr notify({
    required String key,
    required T data,
  }) {
    try {
      return _listeners[key]?.callback.call(data);
    } catch (e) {
      // Only the type: the error may carry request details (overview §2).
      if (kDebugMode) debugPrint('EventNotifier notify error: ${e.runtimeType}');
    }
  }

  int get length => _listeners.length;
  bool get isNotEmpty => _listeners.isNotEmpty;

  FutureOr Function(T)? removeFirst() {
    try {
      final key = _listeners.keys.first;
      final entry = _listeners.remove(key);
      return entry?.callback;
    } catch (e) {
      return null;
    }
  }

  EventDisposer addListener(
    String key,
    FutureOr Function(T) listener, {
    EventPriority priority = EventPriority.normal,
  }) {
    _listeners.putIfAbsent(key, () => _ListenerEntry(listener, priority));
    return EventDisposer(() {
      removeListener(key);
    });
  }

  void removeListener(String key) {
    _listeners.remove(key);
  }

  void removeAll() {
    _listeners.clear();
  }

  void dispose() {
    removeAll();
  }
}

class EventDisposer {
  final Function _delegate;

  EventDisposer(this._delegate);
  void dispose() {
    _delegate.call();
  }
}
