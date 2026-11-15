import 'package:flutter/foundation.dart';

import '../../data/models/dining_table.dart';
import '../../data/models/menu.dart';
import 'status.dart';

@immutable
class MenuState {
  const MenuState({
    this.status = Status.idle,
    this.items = const <MenuItem>[],
    this.query = '',
    this.categoryFilter,
    this.tabIndex = 0,
  });

  final Status status;
  final List<MenuItem> items;

  /// Search + category filter for the *Menu* screen (POS keeps its own).
  final String query;
  final int? categoryFilter;

  /// 0 = Items, 1 = Categories.
  final int tabIndex;

  List<MenuItem> get filtered {
    final String q = query.trim().toLowerCase();
    return items.where((MenuItem i) {
      final bool matchesCategory =
          categoryFilter == null || i.categoryId == categoryFilter;
      final bool matchesQuery =
          q.isEmpty ||
          i.name.toLowerCase().contains(q) ||
          i.description.toLowerCase().contains(q);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  MenuState copyWith({
    Status? status,
    List<MenuItem>? items,
    String? query,
    int? categoryFilter,
    bool clearCategoryFilter = false,
    int? tabIndex,
  }) {
    return MenuState(
      status: status ?? this.status,
      items: items ?? this.items,
      query: query ?? this.query,
      categoryFilter: clearCategoryFilter
          ? null
          : (categoryFilter ?? this.categoryFilter),
      tabIndex: tabIndex ?? this.tabIndex,
    );
  }
}

@immutable
class CategoryState {
  const CategoryState({
    this.status = Status.idle,
    this.categories = const <MenuCategory>[],
  });

  final Status status;
  final List<MenuCategory> categories;

  MenuCategory? byId(int id) {
    for (final MenuCategory c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  CategoryState copyWith({Status? status, List<MenuCategory>? categories}) {
    return CategoryState(
      status: status ?? this.status,
      categories: categories ?? this.categories,
    );
  }
}

@immutable
class TableState {
  const TableState({
    this.status = Status.idle,
    this.tables = const <DiningTable>[],
  });

  final Status status;
  final List<DiningTable> tables;

  DiningTable? byId(int? id) {
    if (id == null) return null;
    for (final DiningTable t in tables) {
      if (t.id == id) return t;
    }
    return null;
  }

  List<DiningTable> get selectable =>
      tables.where((DiningTable t) => t.active).toList();

  TableState copyWith({Status? status, List<DiningTable>? tables}) {
    return TableState(
      status: status ?? this.status,
      tables: tables ?? this.tables,
    );
  }
}
