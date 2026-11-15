import 'package:flutter/foundation.dart';
import 'package:redux/redux.dart';

import 'app_state.dart';
import 'reducers.dart';

Store<AppState> createStore() {
  return Store<AppState>(
    appReducer,
    initialState: const AppState(),
    middleware: <Middleware<AppState>>[if (kDebugMode) _logger],
  );
}

/// Debug-only action log. Kept out of release builds entirely.
void _logger(Store<AppState> store, dynamic action, NextDispatcher next) {
  debugPrint('[redux] ${action.runtimeType}');
  next(action);
}
