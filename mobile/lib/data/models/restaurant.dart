import '../../core/utils/enums.dart';

/// A tenant. Every other record in the app hangs off [id] / [slug]; the API is
/// responsible for enforcing that isolation, the client simply carries it.
class Restaurant {
  const Restaurant({
    required this.id,
    required this.slug,
    required this.name,
    required this.phone,
    required this.address,
    this.isOpen = true,
    this.subscriptionStatus = 'active',
    this.logoEmoji = '🍽️',
  });

  final int id;
  final String slug;
  final String name;
  final String phone;
  final String address;
  final bool isOpen;
  final String subscriptionStatus;
  final String logoEmoji;

  Restaurant copyWith({
    String? name,
    String? phone,
    String? address,
    bool? isOpen,
  }) {
    return Restaurant(
      id: id,
      slug: slug,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      isOpen: isOpen ?? this.isOpen,
      subscriptionStatus: subscriptionStatus,
      logoEmoji: logoEmoji,
    );
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.phone,
    required this.role,
    required this.permissions,
    this.active = true,
  });

  final int id;
  final int restaurantId;
  final String name;
  final String phone;
  final UserRole role;
  final Set<Permission> permissions;
  final bool active;

  bool can(Permission p) => permissions.contains(p);

  bool canAny(Iterable<Permission> ps) => ps.any(permissions.contains);

  String get initials {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  AppUser copyWith({
    UserRole? role,
    Set<Permission>? permissions,
    bool? active,
  }) {
    return AppUser(
      id: id,
      restaurantId: restaurantId,
      name: name,
      phone: phone,
      role: role ?? this.role,
      permissions: permissions ?? this.permissions,
      active: active ?? this.active,
    );
  }
}
