import 'package:flutter/foundation.dart';

import '../../core/utils/enums.dart';
import '../../data/models/restaurant.dart';
import 'status.dart';

/// Where the user is in the sign-in journey.
///
/// The app routes on this and nothing else, so there is exactly one answer to
/// "what should be on screen right now".
enum AuthStage {
  /// Checking for a stored session. Shows the splash, never the login form —
  /// flashing a login screen at someone who is already signed in is jarring.
  restoring,

  signedOut,

  /// Password accepted, waiting on a one-time code.
  awaitingTwoFactor,

  /// A valid session is stored, but this handset is set to ask for a face or
  /// fingerprint first. Not signed out — nothing has been cleared, and the
  /// password route is still there for whoever cannot use the sensor.
  locked,

  signedIn,
}

/// Session and sign-in state.
///
/// `restaurantSlug` is what the API turns into a `restaurant_id`; nothing in
/// the app reads data without it.
@immutable
class AuthState {
  const AuthState({
    this.stage = AuthStage.restoring,
    this.status = Status.idle,
    this.user,
    this.restaurant,
    this.restaurantSlug = '',
    this.phone = '',
    this.challenge,
    this.pendingUserName = '',
    this.pendingRestaurantName = '',
    this.error,
    this.fieldErrors = const <String, String>{},
    this.submitting = false,
    this.mustChangePassword = false,
    this.mustEnrolTwoFactor = false,
  });

  final AuthStage stage;
  final Status status;
  final AppUser? user;
  final Restaurant? restaurant;
  final String restaurantSlug;

  /// Remembered between sign-ins to prefill the form. Never the password.
  final String phone;

  /// The short-lived ticket held between the password step and the code step.
  /// It grants nothing except the right to present an OTP.
  final String? challenge;
  final String pendingUserName;
  final String pendingRestaurantName;

  final String? error;
  final Map<String, String> fieldErrors;
  final bool submitting;

  /// Obligations the server reported at sign-in. The app routes straight to
  /// the screen that resolves them rather than letting someone work and then
  /// blocking them later.
  final bool mustChangePassword;
  final bool mustEnrolTwoFactor;

  bool get isSignedIn => stage == AuthStage.signedIn && user != null;

  /// Every permission check funnels through here, so an unknown session is
  /// denied by default rather than accidentally permissive.
  bool can(Permission p) => user?.can(p) ?? false;

  bool canAny(Iterable<Permission> ps) => user?.canAny(ps) ?? false;

  AuthState copyWith({
    AuthStage? stage,
    Status? status,
    AppUser? user,
    Restaurant? restaurant,
    String? restaurantSlug,
    String? phone,
    String? challenge,
    bool clearChallenge = false,
    String? pendingUserName,
    String? pendingRestaurantName,
    String? error,
    bool clearError = false,
    Map<String, String>? fieldErrors,
    bool? submitting,
    bool? mustChangePassword,
    bool? mustEnrolTwoFactor,
  }) {
    return AuthState(
      stage: stage ?? this.stage,
      status: status ?? this.status,
      user: user ?? this.user,
      restaurant: restaurant ?? this.restaurant,
      restaurantSlug: restaurantSlug ?? this.restaurantSlug,
      phone: phone ?? this.phone,
      challenge: clearChallenge ? null : (challenge ?? this.challenge),
      pendingUserName: pendingUserName ?? this.pendingUserName,
      pendingRestaurantName:
          pendingRestaurantName ?? this.pendingRestaurantName,
      error: clearError ? null : (error ?? this.error),
      fieldErrors: fieldErrors ?? this.fieldErrors,
      submitting: submitting ?? this.submitting,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      mustEnrolTwoFactor: mustEnrolTwoFactor ?? this.mustEnrolTwoFactor,
    );
  }
}

@immutable
class RestaurantState {
  const RestaurantState({
    this.status = Status.idle,
    this.restaurant,
    this.staff = const <AppUser>[],
  });

  final Status status;
  final Restaurant? restaurant;
  final List<AppUser> staff;

  List<AppUser> get waiters =>
      staff.where((AppUser u) => u.role == UserRole.waiter).toList();

  RestaurantState copyWith({
    Status? status,
    Restaurant? restaurant,
    List<AppUser>? staff,
  }) {
    return RestaurantState(
      status: status ?? this.status,
      restaurant: restaurant ?? this.restaurant,
      staff: staff ?? this.staff,
    );
  }
}
