import 'dart:ui';

class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.emoji,
    required this.color,
    this.description = '',
    this.active = true,
    this.sortOrder = 0,
  });

  final int id;
  final int restaurantId;
  final String name;
  final String emoji;
  final Color color;
  final String description;
  final bool active;
  final int sortOrder;

  MenuCategory copyWith({
    String? name,
    String? description,
    bool? active,
    int? sortOrder,
  }) {
    return MenuCategory(
      id: id,
      restaurantId: restaurantId,
      name: name ?? this.name,
      emoji: emoji,
      color: color,
      description: description ?? this.description,
      active: active ?? this.active,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.restaurantId,
    required this.categoryId,
    required this.name,
    required this.price,
    this.description = '',
    this.imageUrl,
    this.emoji = '🍽️',
    this.available = true,
    this.applyPackagingFee = true,
    this.sortOrder = 0,
  });

  final int id;
  final int restaurantId;
  final int categoryId;
  final String name;
  final double price;
  final String description;

  /// Remote image served by the API. Absent or unreachable images fall back to
  /// a branded [emoji] tile, so the POS still looks finished offline.
  final String? imageUrl;
  final String emoji;
  final bool available;
  final bool applyPackagingFee;
  final int sortOrder;

  MenuItem copyWith({
    int? categoryId,
    String? name,
    double? price,
    String? description,
    bool? available,
    bool? applyPackagingFee,
  }) {
    return MenuItem(
      id: id,
      restaurantId: restaurantId,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      price: price ?? this.price,
      description: description ?? this.description,
      imageUrl: imageUrl,
      emoji: emoji,
      available: available ?? this.available,
      applyPackagingFee: applyPackagingFee ?? this.applyPackagingFee,
      sortOrder: sortOrder,
    );
  }
}
