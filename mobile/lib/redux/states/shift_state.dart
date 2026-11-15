import 'package:flutter/foundation.dart';

import '../../data/models/shift.dart';
import '../../data/repository/dacaam_repository.dart';
import 'status.dart';

/// The till: whether it is open, and what it has done before.
///
/// [status.shift] deliberately carries no expected total while a shift is
/// open. The server does not send it to whoever is about to count the drawer,
/// and this state does not invent one — a screen that could display the figure
/// would eventually display it.
@immutable
class ShiftState {
  const ShiftState({
    this.status = Status.idle,
    this.till,
    this.history = const <Shift>[],
    this.lastClosed,
    this.tillOpenHint = false,
  });

  final Status status;

  /// What the till looks like now. Null until it has been asked.
  final ShiftStatus? till;

  final List<Shift> history;

  /// The shift that was just closed, so the screen can show the figures once —
  /// the one moment the expected total is allowed to be on screen.
  final Shift? lastClosed;

  /// Whether a till is open, from the session payload.
  ///
  /// The full status needs shifts.manage, which a waiter does not have —
  /// their request 403s and leaves [till] null. Falling back to false there
  /// told every waiter the till was shut all day, on every day.
  final bool tillOpenHint;

  bool get isOpen => till?.isOpen ?? tillOpenHint;
  Shift? get open => till?.shift;

  /// What the previous person counted. What this one is starting from.
  double? get lastClose => till?.lastClose;

  ShiftState copyWith({
    Status? status,
    ShiftStatus? till,
    List<Shift>? history,
    Shift? lastClosed,
    bool? tillOpenHint,
    bool clearLastClosed = false,
  }) {
    return ShiftState(
      status: status ?? this.status,
      till: till ?? this.till,
      history: history ?? this.history,
      lastClosed: clearLastClosed ? null : (lastClosed ?? this.lastClosed),
      tillOpenHint: tillOpenHint ?? this.tillOpenHint,
    );
  }
}
