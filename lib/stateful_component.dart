library stateful_component;

import 'dart:async';
import 'dart:collection' show HashSet;
import 'dart:ui' show VoidCallback;

import 'package:flutter/foundation.dart' hide ObserverList;
import 'package:flutter/widgets.dart'
    show InheritedWidget, BuildContext, Builder, State, StatefulWidget, Widget;

/// A list optimized for containment queries.
///
/// Consider using an [_ObserverList] instead of a [List] when the number of
/// [contains] calls dominates the number of [add] and [remove] calls.
class _ObserverList<T> extends Iterable<T> {
  final List<T> _list = <T>[];
  bool _isDirty = false;
  HashSet<T> _set;

  @override
  bool get isEmpty => _list.isEmpty;

  @override
  bool get isNotEmpty => _list.isNotEmpty;

  @override
  int get length => _list.length;

  /// Adds an item to the end of this list.
  ///
  /// The given item must not already be in the list.
  void add(T item) {
    _isDirty = true;
    _list.add(item);
  }

  /// Removes an item from the list.
  ///
  /// Returns whether the item was present in the list.
  bool remove(T item) {
    _isDirty = true;
    return _list.remove(item);
  }

  @override
  bool contains(Object item) {
    if (_list.length < 3) return _list.contains(item);

    if (_isDirty) {
      if (_set == null) {
        _set = new HashSet<T>.from(_list);
      } else {
        _set.clear();
        _set.addAll(_list);
      }
      _isDirty = false;
    }

    return _set.contains(item);
  }

  @override
  Iterator<T> get iterator => _list.iterator;
}

/// A stateful component is a component separate from the widget tree that
/// maintains application state. Like a normal [State] for a [StatefulWidget],
/// you must call [setState] to update the state of your stateful component.
///
/// To use your stateful component, first provide it to a widget tree using a
/// [ComponentProvider], then use a [ComponentBuilder] to access your stateful
/// component (or a subset of).
///
/// Please read the [ComponentProvider] and [ComponentBuilder] documentation for
/// more information.
abstract class StatefulComponent {
  _ObserverList<VoidCallback> _listeners = new _ObserverList<VoidCallback>();

  bool _debugAssertNotDisposed() {
    assert(() {
      if (_listeners == null) {
        throw new FlutterError(
          'A $runtimeType was used after being disposed.\n'
              'Once you have called dispose() on a $runtimeType, it can no longer be used.',
        );
      }
      return true;
    }());
    return true;
  }

  /// Register a closure to be called when the object changes.
  ///
  /// This method must not be called after [dispose] has been called.
  void addListener(VoidCallback listener) {
    assert(_debugAssertNotDisposed());
    _listeners.add(listener);

    if (_listeners.length == 1) {
      onActivated();
    }
  }

  /// Remove a previously registered closure from the list of closures that are
  /// notified when the object changes.
  ///
  /// If the given listener is not registered, the call is ignored.
  ///
  /// This method must not be called after [dispose] has been called.
  ///
  /// If a listener had been added twice, and is removed once during an
  /// iteration (i.e. in response to a notification), it will still be called
  /// again. If, on the other hand, it is removed as many times as it was
  /// registered, then it will no longer be called. This odd behavior is the
  /// result of the [ChangeNotifier] not being able to determine which listener
  /// is being removed, since they are identical, and therefore conservatively
  /// still calling all the listeners when it knows that any are still
  /// registered.
  ///
  /// This surprising behavior can be unexpectedly observed when registering a
  /// listener on two separate objects which are both forwarding all
  /// registrations to a common upstream object.
  void removeListener(VoidCallback listener) {
    assert(_debugAssertNotDisposed());
    bool removed = _listeners.remove(listener);

    if (removed && _listeners.isEmpty) {
      onDeactivated();
    }
  }

  /// Discards any resources used by the object. After this is called, the
  /// object is not in a usable state and should be discarded (calls to
  /// [addListener] and [removeListener] will throw after the object is
  /// disposed).
  ///
  /// This method should only be called by the object's owner.
  @mustCallSuper
  void dispose() {
    assert(_debugAssertNotDisposed());
    _listeners = null;
  }

  /// Call all the registered listeners.
  ///
  /// Call this method whenever the object changes, to notify any clients the
  /// object may have. Listeners that are added during this iteration will not
  /// be visited. Listeners that are removed during this iteration will not be
  /// visited after they are removed.
  ///
  /// Exceptions thrown by listeners will be caught and reported using
  /// [FlutterError.reportError].
  ///
  /// This method must not be called after [dispose] has been called.
  ///
  /// Surprising behavior can result when reentrantly removing a listener (i.e.
  /// in response to a notification) that has been registered multiple times.
  /// See the discussion at [removeListener].
  void _notifyListeners() {
    assert(_debugAssertNotDisposed());
    if (_listeners != null) {
      final List<VoidCallback> localListeners =
          new List<VoidCallback>.from(_listeners);
      for (VoidCallback listener in localListeners) {
        try {
          if (_listeners.contains(listener)) listener();
        } catch (exception, stack) {
          FlutterError.reportError(new FlutterErrorDetails(
            exception: exception,
            stack: stack,
            library: 'stateful component library',
            context: 'while dispatching notifications for $runtimeType',
            informationCollector: (StringBuffer information) {
              information.writeln('The $runtimeType sending notification was:');
              information.write('  $this');
            },
          ));
        }
      }
    }
  }

  @protected
  void setState(VoidCallback callback) {
    callback();
    _notifyListeners();
  }

  /// Called when your stateful component gains its first listener.
  @protected
  void onActivated() {}

  /// Called when your stateful component loses its last listener.
  @protected
  void onDeactivated() {}
}

/// A stateful component where state changes using [setState] are delayed until
/// the next microtask, effectively batching state changes and dispatching them
/// all at once.
abstract class BatchedStatefulComponent extends StatefulComponent {
  final _callbacks = <VoidCallback>[];
  bool _posted = false;

  @override
  void setState(VoidCallback callback) {
    _callbacks.add(callback);
    if (!_posted) {
      scheduleMicrotask(() {
        _posted = false;
        final len = _callbacks.length;
        for (int i=0; i<len; i++) {
          _callbacks[i]();
        }
        _callbacks.removeRange(0, len);
        onBatchFinished();
        _notifyListeners();
      });
      _posted = true;
    }
  }

  /// Called when the latest state update batch has completed.
  @protected
  void onBatchFinished() {}
}

/// Provides the given stateful component to the given widget tree.
///
/// This class requires proper type arguments.
class ComponentProvider<T extends StatefulComponent> extends InheritedWidget {
  final T component;

  const ComponentProvider({
    Key key,
    Widget child,
    this.component,
  }) : super(key: key, child: child);

  @override
  bool updateShouldNotify(ComponentProvider<T> oldWidget) {
    return !identical(oldWidget.component, component);
  }

  T of(BuildContext context) {
    return (context.inheritFromWidgetOfExactType(runtimeType)
            as ComponentProvider<T>)
        ?.component;
  }
}

typedef ComponentAccessor<T extends StatefulComponent, V> = V Function(
    T component);
typedef ComponentWidgetBuilder<T> = Widget Function(
    BuildContext context, T value);

/// Listens to the given [StatefulComponent] or the component provided by the
/// nearest [ComponentProvider]. Uses a [ComponentAccessor] to narrow down the
/// part of the state that is listened to for fine-grained updates, and passes
/// the newly accessed value to the given [ComponentWidgetBuilder].
///
/// This class requires proper type arguments.
class ComponentBuilder<T extends StatefulComponent, V> extends StatefulWidget {
  final T component;
  final ComponentAccessor<T, V> accessor;
  final ComponentWidgetBuilder<V> builder;
  final bool accessIfNull;

  const ComponentBuilder({
    Key key,
    this.component,
    @required this.accessor,
    @required this.builder,
    this.accessIfNull: false,
  }) : super(key: key);

  @override
  _ComponentBuilderState createState() => new _ComponentBuilderState<T, V>();
}

class _ComponentBuilderState<T extends StatefulComponent, V>
    extends State<ComponentBuilder<T, V>> {
  T component;
  V value;

  V getNewValue() => (component != null || widget.accessIfNull)
      ? widget.accessor(component)
      : null;

  void onChange() {
    final newValue = getNewValue();

    if (newValue != value) {
      setState(() {
        value = newValue;
      });
    }
  }

  void disconnectComponent() {
    if (component != null) {
      component.removeListener(onChange);
      component = null;
    }
  }

  void connectComponent(T component) {
    if (identical(component, this.component)) return;

    if (this.component != null) disconnectComponent();
    this.component = component;
    component?.addListener(onChange);
    onChange();
  }

  @override
  Widget build(BuildContext context) {
    return new Builder(
      builder: (context) => widget.builder(context, value),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    connectComponent(
        widget.component ?? new ComponentProvider<T>().of(context));
  }

  @override
  void didUpdateWidget(ComponentBuilder oldWidget) {
    if (!identical(widget.component, oldWidget.component)) {
      disconnectComponent();
      connectComponent(widget.component);
    }
  }

  @override
  void dispose() {
    disconnectComponent();
    super.dispose();
  }
}
