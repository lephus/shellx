import 'package:equatable/equatable.dart';

/// The signed-in account as persisted in secure storage (spec §9.5). One opaque device token,
/// no refresh token.
final class AccountSession extends Equatable {
  const AccountSession({
    required this.userId,
    required this.deviceId,
    required this.token,
    required this.email,
  });

  final String userId;
  final String deviceId;
  final String token;
  final String email;

  @override
  List<Object?> get props => [userId, deviceId, token, email];

  /// Never includes the token: a session must not end up in a log line with it (overview §2).
  @override
  String toString() => 'AccountSession(userId: $userId, deviceId: $deviceId)';
}
