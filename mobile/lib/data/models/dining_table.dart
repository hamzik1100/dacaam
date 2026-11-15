import '../../core/utils/enums.dart';

/// Named `DiningTable` to avoid colliding with Flutter's `Table` widget.
class DiningTable {
  const DiningTable({
    required this.id,
    required this.restaurantId,
    required this.number,
    required this.capacity,
    this.name = '',
    this.status = TableStatus.available,
    this.currentOrderId,
    this.active = true,
  });

  final int id;
  final int restaurantId;
  final int number;
  final int capacity;
  final String name;
  final TableStatus status;
  final int? currentOrderId;
  final bool active;

  String get label =>
      name.isNotEmpty ? name : 'Table ${number.toString().padLeft(2, '0')}';

  DiningTable copyWith({
    TableStatus? status,
    int? currentOrderId,
    bool? active,
  }) {
    return DiningTable(
      id: id,
      restaurantId: restaurantId,
      number: number,
      capacity: capacity,
      name: name,
      status: status ?? this.status,
      currentOrderId: currentOrderId ?? this.currentOrderId,
      active: active ?? this.active,
    );
  }
}
