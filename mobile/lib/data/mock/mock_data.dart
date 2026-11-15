import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/enums.dart';
import '../models/analytics.dart';
import '../models/dining_table.dart';
import '../models/finance.dart';
import '../models/menu.dart';
import '../models/order.dart';
import '../models/restaurant.dart';

/// Seeded demo tenant used until the REST API lands in Phase 2.
///
/// Everything here is scoped to `restaurantId: 1` (slug `HAMZE`) exactly the
/// way the API will scope it, so swapping this class for a repository backed
/// by HTTP is a drop-in change — the reducers and widgets never learn where
/// the data came from.
///
/// Menu images are intentionally left null: the emoji tile fallback keeps the
/// POS looking finished offline, and Phase 2 fills `imageUrl` from the API.
class MockData {
  const MockData._();

  static const int restaurantId = 1;

  static DateTime get _now => DateTime.now();

  static DateTime _minutesAgo(int m) => _now.subtract(Duration(minutes: m));

  // ---------------------------------------------------------------- tenant

  static const Restaurant restaurant = Restaurant(
    id: restaurantId,
    slug: 'HAMZE',
    name: 'Hamze Restaurant',
    phone: '063 4567890',
    address: 'Jigjiga Yar, Hargeysa',
    logoEmoji: '🍔',
  );

  // ----------------------------------------------------------------- users

  static final List<AppUser> users = <AppUser>[
    AppUser(
      id: 1,
      restaurantId: restaurantId,
      name: 'Axmed Xasan',
      phone: '063 4567890',
      role: UserRole.admin,
      permissions: Permission.forRole(UserRole.admin),
    ),
    AppUser(
      id: 2,
      restaurantId: restaurantId,
      name: 'Faadumo Cali',
      phone: '063 1122334',
      role: UserRole.operator,
      permissions: Permission.forRole(UserRole.operator),
    ),
    AppUser(
      id: 3,
      restaurantId: restaurantId,
      name: 'Abdullahi Warsame',
      phone: '063 2233445',
      role: UserRole.waiter,
      permissions: Permission.forRole(UserRole.waiter),
    ),
    AppUser(
      id: 4,
      restaurantId: restaurantId,
      name: 'Omar Jaamac',
      phone: '063 3344556',
      role: UserRole.waiter,
      permissions: Permission.forRole(UserRole.waiter),
    ),
    AppUser(
      id: 5,
      restaurantId: restaurantId,
      name: 'Hamze Cabdi',
      phone: '063 4455667',
      role: UserRole.waiter,
      permissions: Permission.forRole(UserRole.waiter),
    ),
  ];

  static AppUser get currentUser => users.first;

  static List<AppUser> get waiters =>
      users.where((AppUser u) => u.role == UserRole.waiter).toList();

  // ------------------------------------------------------------ categories

  static const List<MenuCategory> categories = <MenuCategory>[
    MenuCategory(
      id: 1,
      restaurantId: restaurantId,
      name: 'Burgers',
      emoji: '🍔',
      color: AppColors.primary,
      description: 'Beef and chicken burgers',
      sortOrder: 1,
    ),
    MenuCategory(
      id: 2,
      restaurantId: restaurantId,
      name: 'Pizzas',
      emoji: '🍕',
      color: AppColors.secondary,
      description: 'Stone baked pizzas',
      sortOrder: 2,
    ),
    MenuCategory(
      id: 3,
      restaurantId: restaurantId,
      name: 'Chicken',
      emoji: '🍗',
      color: AppColors.teal,
      description: 'Grilled and fried chicken',
      sortOrder: 3,
    ),
    MenuCategory(
      id: 4,
      restaurantId: restaurantId,
      name: 'Drinks',
      emoji: '🥤',
      color: AppColors.info,
      description: 'Juices, tea and soft drinks',
      sortOrder: 4,
    ),
    MenuCategory(
      id: 5,
      restaurantId: restaurantId,
      name: 'Desserts',
      emoji: '🍰',
      color: AppColors.violet,
      description: 'Cakes and ice cream',
      sortOrder: 5,
    ),
    MenuCategory(
      id: 6,
      restaurantId: restaurantId,
      name: 'Sides',
      emoji: '🍟',
      color: AppColors.success,
      description: 'Fries, salad and rice',
      sortOrder: 6,
    ),
  ];

  static MenuCategory categoryById(int id) =>
      categories.firstWhere((MenuCategory c) => c.id == id);

  // ------------------------------------------------------------ menu items

  static const List<MenuItem> menuItems = <MenuItem>[
    // Burgers
    MenuItem(
      id: 1,
      restaurantId: restaurantId,
      categoryId: 1,
      name: 'Chicken Burger',
      price: 35000,
      emoji: '🍔',
      description: 'Chicken burger with fries',
    ),
    MenuItem(
      id: 2,
      restaurantId: restaurantId,
      categoryId: 1,
      name: 'Beef Burger',
      price: 40000,
      emoji: '🍔',
      description: 'Grilled beef patty, cheddar, house sauce',
    ),
    MenuItem(
      id: 3,
      restaurantId: restaurantId,
      categoryId: 1,
      name: 'Cheese Burger',
      price: 38000,
      emoji: '🧀',
      description: 'Double cheese with caramelised onion',
    ),
    // Pizzas
    MenuItem(
      id: 4,
      restaurantId: restaurantId,
      categoryId: 2,
      name: 'Chicken Pizza',
      price: 45000,
      emoji: '🍕',
      description: 'Chicken, mozzarella, peppers',
    ),
    MenuItem(
      id: 5,
      restaurantId: restaurantId,
      categoryId: 2,
      name: 'Margherita Pizza',
      price: 50000,
      emoji: '🍕',
      description: 'Tomato, basil, fresh mozzarella',
    ),
    MenuItem(
      id: 6,
      restaurantId: restaurantId,
      categoryId: 2,
      name: 'Beef Pizza',
      price: 55000,
      emoji: '🍕',
      description: 'Minced beef, onion, olives',
    ),
    // Chicken
    MenuItem(
      id: 7,
      restaurantId: restaurantId,
      categoryId: 3,
      name: 'Digaag Duban',
      price: 60000,
      emoji: '🍗',
      description: 'Half grilled chicken with rice',
    ),
    MenuItem(
      id: 8,
      restaurantId: restaurantId,
      categoryId: 3,
      name: 'Chicken Wings',
      price: 30000,
      emoji: '🍗',
      description: 'Eight spicy wings',
    ),
    MenuItem(
      id: 9,
      restaurantId: restaurantId,
      categoryId: 3,
      name: 'Chicken Shawarma',
      price: 25000,
      emoji: '🌯',
      description: 'Shawarma wrap with garlic sauce',
    ),
    // Drinks
    MenuItem(
      id: 10,
      restaurantId: restaurantId,
      categoryId: 4,
      name: 'Fresh Juice',
      price: 20000,
      emoji: '🧃',
      description: 'Mango, avocado or mixed',
    ),
    MenuItem(
      id: 11,
      restaurantId: restaurantId,
      categoryId: 4,
      name: 'Shaah Somali',
      price: 8000,
      emoji: '☕',
      description: 'Spiced Somali tea',
      applyPackagingFee: false,
    ),
    MenuItem(
      id: 12,
      restaurantId: restaurantId,
      categoryId: 4,
      name: 'Soft Drink',
      price: 10000,
      emoji: '🥤',
      description: 'Chilled 300ml bottle',
      applyPackagingFee: false,
    ),
    MenuItem(
      id: 13,
      restaurantId: restaurantId,
      categoryId: 4,
      name: 'Water',
      price: 5000,
      emoji: '💧',
      description: '500ml mineral water',
      applyPackagingFee: false,
    ),
    // Desserts
    MenuItem(
      id: 14,
      restaurantId: restaurantId,
      categoryId: 5,
      name: 'Chocolate Cake',
      price: 25000,
      emoji: '🍰',
      description: 'Rich chocolate sponge',
    ),
    MenuItem(
      id: 15,
      restaurantId: restaurantId,
      categoryId: 5,
      name: 'Ice Cream',
      price: 15000,
      emoji: '🍨',
      description: 'Two scoops, choice of flavour',
      available: false,
    ),
    // Sides
    MenuItem(
      id: 16,
      restaurantId: restaurantId,
      categoryId: 6,
      name: 'French Fries',
      price: 15000,
      emoji: '🍟',
      description: 'Crispy salted fries',
    ),
    MenuItem(
      id: 17,
      restaurantId: restaurantId,
      categoryId: 6,
      name: 'Salad',
      price: 12000,
      emoji: '🥗',
      description: 'Garden salad with lemon dressing',
    ),
    MenuItem(
      id: 18,
      restaurantId: restaurantId,
      categoryId: 6,
      name: 'Bariis',
      price: 18000,
      emoji: '🍚',
      description: 'Somali spiced rice',
    ),
  ];

  static MenuItem itemById(int id) =>
      menuItems.firstWhere((MenuItem i) => i.id == id);

  // ---------------------------------------------------------------- tables

  static const List<DiningTable> tables = <DiningTable>[
    DiningTable(
      id: 1,
      restaurantId: restaurantId,
      number: 1,
      capacity: 4,
      status: TableStatus.occupied,
      currentOrderId: 1021,
    ),
    DiningTable(id: 2, restaurantId: restaurantId, number: 2, capacity: 2),
    DiningTable(
      id: 3,
      restaurantId: restaurantId,
      number: 3,
      capacity: 4,
      status: TableStatus.occupied,
      currentOrderId: 1025,
    ),
    DiningTable(
      id: 4,
      restaurantId: restaurantId,
      number: 4,
      capacity: 6,
      status: TableStatus.reserved,
    ),
    DiningTable(id: 5, restaurantId: restaurantId, number: 5, capacity: 2),
    DiningTable(
      id: 6,
      restaurantId: restaurantId,
      number: 6,
      capacity: 8,
      status: TableStatus.occupied,
      currentOrderId: 1023,
    ),
    DiningTable(id: 7, restaurantId: restaurantId, number: 7, capacity: 4),
    DiningTable(id: 8, restaurantId: restaurantId, number: 8, capacity: 4),
    DiningTable(
      id: 9,
      restaurantId: restaurantId,
      number: 9,
      capacity: 2,
      status: TableStatus.disabled,
      active: false,
    ),
    DiningTable(id: 10, restaurantId: restaurantId, number: 10, capacity: 6),
    DiningTable(
      id: 11,
      restaurantId: restaurantId,
      number: 11,
      capacity: 4,
      status: TableStatus.reserved,
    ),
    DiningTable(
      id: 12,
      restaurantId: restaurantId,
      number: 12,
      capacity: 10,
      name: 'VIP Hall',
    ),
  ];

  // ---------------------------------------------------------------- orders

  static OrderLine _line(int itemId, int qty) =>
      OrderLine.fromMenuItem(itemById(itemId), quantity: qty);

  /// Built once per app launch so relative timestamps ("2 min ago") stay
  /// stable while the user navigates.
  static final List<RestaurantOrder> orders = _buildOrders();

  static List<RestaurantOrder> _buildOrders() {
    final DateTime now = _now;
    return <RestaurantOrder>[
      RestaurantOrder(
        id: 1025,
        number: 1025,
        restaurantId: restaurantId,
        type: OrderType.dineIn,
        status: OrderStatus.preparing,
        tableId: 3,
        tableLabel: 'Table 3',
        waiterName: 'Abdullahi',
        guests: 3,
        createdAt: _minutesAgo(2),
        lines: <OrderLine>[_line(1, 1), _line(16, 2), _line(10, 1)],
        events: <OrderEvent>[
          OrderEvent(
            labelKey: 'orderCreated',
            at: _minutesAgo(2),
            byUser: 'Abdullahi',
          ),
          OrderEvent(
            labelKey: 'itemAdded',
            at: _minutesAgo(2),
            byUser: 'Abdullahi',
            newValue: 'French Fries × 1',
          ),
          OrderEvent(
            labelKey: 'quantityChanged',
            at: _minutesAgo(1),
            byUser: 'Abdullahi',
            oldValue: '1',
            newValue: '2',
            reason: 'Macmiilku wuu kordhiyay',
          ),
        ],
      ),
      RestaurantOrder(
        id: 1024,
        number: 1024,
        restaurantId: restaurantId,
        type: OrderType.takeaway,
        status: OrderStatus.ready,
        waiterName: 'Hamze',
        customerName: 'Maxamed',
        customerPhone: '063 7788990',
        packagingFee: 5000,
        createdAt: _minutesAgo(10),
        lines: <OrderLine>[_line(9, 1), _line(17, 1)],
        events: <OrderEvent>[
          OrderEvent(
            labelKey: 'orderCreated',
            at: _minutesAgo(10),
            byUser: 'Hamze',
          ),
          OrderEvent(
            labelKey: 'orderStatusChanged',
            at: _minutesAgo(4),
            byUser: 'Hamze',
            oldValue: 'Preparing',
            newValue: 'Ready',
          ),
        ],
      ),
      RestaurantOrder(
        id: 1023,
        number: 1023,
        restaurantId: restaurantId,
        type: OrderType.dineIn,
        status: OrderStatus.preparing,
        tableId: 6,
        tableLabel: 'Table 6',
        waiterName: 'Omar',
        guests: 6,
        createdAt: _minutesAgo(15),
        lines: <OrderLine>[_line(6, 1), _line(4, 1), _line(10, 1)],
        events: <OrderEvent>[
          OrderEvent(
            labelKey: 'orderCreated',
            at: _minutesAgo(15),
            byUser: 'Omar',
          ),
        ],
      ),
      RestaurantOrder(
        id: 1022,
        number: 1022,
        restaurantId: restaurantId,
        type: OrderType.takeaway,
        status: OrderStatus.completed,
        waiterName: 'Hamze',
        packagingFee: 5000,
        createdAt: _minutesAgo(20),
        lines: <OrderLine>[_line(8, 1)],
        payments: <OrderPaymentEntry>[
          OrderPaymentEntry(
            method: PaymentMethod.zaad,
            amount: 35000,
            reference: 'ZD-88213',
            at: _minutesAgo(19),
          ),
        ],
        events: <OrderEvent>[
          OrderEvent(
            labelKey: 'orderCreated',
            at: _minutesAgo(20),
            byUser: 'Hamze',
          ),
          OrderEvent(
            labelKey: 'paymentAdded',
            at: _minutesAgo(19),
            byUser: 'Hamze',
            newValue: 'Zaad · SLSH 35,000',
          ),
          OrderEvent(
            labelKey: 'orderStatusChanged',
            at: _minutesAgo(19),
            byUser: 'Hamze',
            oldValue: 'Ready',
            newValue: 'Completed',
          ),
        ],
      ),
      RestaurantOrder(
        id: 1021,
        number: 1021,
        restaurantId: restaurantId,
        type: OrderType.dineIn,
        status: OrderStatus.completed,
        tableId: 1,
        tableLabel: 'Table 1',
        waiterName: 'Abdullahi',
        guests: 2,
        createdAt: _minutesAgo(25),
        lines: <OrderLine>[_line(7, 1), _line(13, 1)],
        payments: <OrderPaymentEntry>[
          OrderPaymentEntry(
            method: PaymentMethod.cash,
            amount: 65000,
            at: _minutesAgo(24),
          ),
        ],
        events: <OrderEvent>[
          OrderEvent(
            labelKey: 'orderCreated',
            at: _minutesAgo(25),
            byUser: 'Abdullahi',
          ),
          OrderEvent(
            labelKey: 'paymentAdded',
            at: _minutesAgo(24),
            byUser: 'Abdullahi',
            newValue: 'Cash · SLSH 65,000',
          ),
        ],
      ),
      RestaurantOrder(
        id: 1020,
        number: 1020,
        restaurantId: restaurantId,
        type: OrderType.dineIn,
        status: OrderStatus.cancelled,
        tableId: 4,
        tableLabel: 'Table 4',
        waiterName: 'Omar',
        guests: 2,
        createdAt: _minutesAgo(30),
        cancelReason: 'Macmiilku wuu ka noqday dalabka',
        lines: <OrderLine>[_line(10, 1), _line(11, 1)],
        events: <OrderEvent>[
          OrderEvent(
            labelKey: 'orderCreated',
            at: _minutesAgo(30),
            byUser: 'Omar',
          ),
          OrderEvent(
            labelKey: 'orderStatusChanged',
            at: _minutesAgo(27),
            byUser: 'Omar',
            oldValue: 'Pending',
            newValue: 'Cancelled',
            reason: 'Macmiilku wuu ka noqday dalabka',
          ),
        ],
      ),
      RestaurantOrder(
        id: 1019,
        number: 1019,
        restaurantId: restaurantId,
        type: OrderType.takeaway,
        status: OrderStatus.completed,
        waiterName: 'Hamze',
        customerName: 'Khadra',
        // An account customer who paid at the till. Both facts matter: she has
        // a ledger, and this particular order never touched it.
        customerId: 2,
        packagingFee: 5000,
        createdAt: _minutesAgo(52),
        lines: <OrderLine>[_line(2, 2), _line(16, 1)],
        payments: <OrderPaymentEntry>[
          OrderPaymentEntry(
            method: PaymentMethod.edahab,
            amount: 100000,
            reference: 'ED-44120',
            at: _minutesAgo(51),
          ),
        ],
      ),
      RestaurantOrder(
        id: 1018,
        number: 1018,
        restaurantId: restaurantId,
        type: OrderType.dineIn,
        status: OrderStatus.completed,
        tableId: 8,
        tableLabel: 'Table 8',
        waiterName: 'Abdullahi',
        guests: 4,
        discount: 5000,
        createdAt: _minutesAgo(75),
        lines: <OrderLine>[_line(5, 1), _line(12, 2), _line(14, 1)],
        payments: <OrderPaymentEntry>[
          OrderPaymentEntry(
            method: PaymentMethod.cash,
            amount: 90000,
            at: _minutesAgo(74),
          ),
        ],
      ),
      RestaurantOrder(
        id: 1017,
        number: 1017,
        restaurantId: restaurantId,
        type: OrderType.dineIn,
        status: OrderStatus.pending,
        tableId: 10,
        tableLabel: 'Table 10',
        waiterName: 'Omar',
        guests: 5,
        createdAt: _minutesAgo(96),
        lines: <OrderLine>[_line(18, 2), _line(7, 1)],
      ),
      RestaurantOrder(
        id: 1016,
        number: 1016,
        restaurantId: restaurantId,
        type: OrderType.takeaway,
        status: OrderStatus.completed,
        waiterName: 'Hamze',
        packagingFee: 5000,
        createdAt: now.subtract(const Duration(hours: 3, minutes: 12)),
        lines: <OrderLine>[_line(3, 1), _line(10, 2)],
        payments: <OrderPaymentEntry>[
          OrderPaymentEntry(
            method: PaymentMethod.zaad,
            amount: 83000,
            reference: 'ZD-88190',
          ),
        ],
      ),
      RestaurantOrder(
        id: 1015,
        number: 1015,
        restaurantId: restaurantId,
        type: OrderType.dineIn,
        status: OrderStatus.completed,
        tableId: 2,
        tableLabel: 'Table 2',
        waiterName: 'Abdullahi',
        guests: 2,
        createdAt: now.subtract(const Duration(hours: 4, minutes: 5)),
        lines: <OrderLine>[_line(1, 2), _line(11, 2)],
        payments: <OrderPaymentEntry>[
          OrderPaymentEntry(method: PaymentMethod.cash, amount: 86000),
        ],
      ),
      RestaurantOrder(
        id: 1014,
        number: 1014,
        restaurantId: restaurantId,
        type: OrderType.takeaway,
        status: OrderStatus.cancelled,
        waiterName: 'Omar',
        packagingFee: 5000,
        cancelReason: 'Alaabtii way dhammaatay',
        createdAt: now.subtract(const Duration(hours: 5, minutes: 40)),
        lines: <OrderLine>[_line(15, 2)],
      ),
      RestaurantOrder(
        id: 1013,
        number: 1013,
        restaurantId: restaurantId,
        type: OrderType.dineIn,
        status: OrderStatus.completed,
        tableId: 12,
        tableLabel: 'VIP Hall',
        waiterName: 'Faadumo',
        guests: 9,
        discount: 20000,
        createdAt: now.subtract(const Duration(days: 1, hours: 2)),
        lines: <OrderLine>[_line(7, 3), _line(18, 3), _line(10, 4)],
        payments: <OrderPaymentEntry>[
          OrderPaymentEntry(
            method: PaymentMethod.bank,
            amount: 294000,
            reference: 'BK-2291',
          ),
        ],
      ),
      RestaurantOrder(
        id: 1012,
        number: 1012,
        restaurantId: restaurantId,
        type: OrderType.takeaway,
        status: OrderStatus.completed,
        waiterName: 'Hamze',
        packagingFee: 5000,
        createdAt: now.subtract(const Duration(days: 1, hours: 6)),
        lines: <OrderLine>[_line(9, 3), _line(12, 3)],
        payments: <OrderPaymentEntry>[
          OrderPaymentEntry(
            method: PaymentMethod.edahab,
            amount: 110000,
            reference: 'ED-44001',
          ),
        ],
      ),
    ];
  }

  // ---------------------------------------------------------------- drafts

  static final List<DraftOrder> drafts = <DraftOrder>[
    DraftOrder(
      id: 102,
      code: 'D-102',
      restaurantId: restaurantId,
      customerName: 'Mohamed',
      customerPhone: '063 5566778',
      type: OrderType.takeaway,
      packagingApplied: true,
      waiterName: 'Hamze',
      notes: 'Wuxuu soo qaadan doonaa 19:30',
      createdAt: _minutesAgo(45),
      lines: <OrderLine>[_line(1, 2), _line(10, 2)],
    ),
    DraftOrder(
      id: 101,
      code: 'D-101',
      restaurantId: restaurantId,
      customerName: 'Saynab',
      customerPhone: '063 9988776',
      type: OrderType.dineIn,
      tableLabel: 'Table 7',
      waiterName: 'Abdullahi',
      status: DraftStatus.pending,
      createdAt: _minutesAgo(140),
      lines: <OrderLine>[_line(5, 1), _line(17, 2), _line(11, 3)],
    ),
    DraftOrder(
      id: 100,
      code: 'D-100',
      restaurantId: restaurantId,
      customerName: 'Cabdiraxmaan',
      type: OrderType.takeaway,
      packagingApplied: true,
      waiterName: 'Omar',
      createdAt: _minutesAgo(320),
      lines: <OrderLine>[_line(8, 4)],
    ),
  ];

  // -------------------------------------------------------------- expenses

  static const List<ExpenseCategory> expenseCategories = <ExpenseCategory>[
    ExpenseCategory(
      id: 1,
      name: 'Food Supplies',
      icon: Icons.local_grocery_store_rounded,
      color: AppColors.primary,
      kind: ExpenseKind.daily,
    ),
    ExpenseCategory(
      id: 2,
      name: 'Cleaning',
      icon: Icons.cleaning_services_rounded,
      color: AppColors.info,
      kind: ExpenseKind.daily,
    ),
    ExpenseCategory(
      id: 3,
      name: 'Transport',
      icon: Icons.local_shipping_rounded,
      color: AppColors.teal,
      kind: ExpenseKind.daily,
    ),
    ExpenseCategory(
      id: 4,
      name: 'Rent',
      icon: Icons.home_work_rounded,
      color: AppColors.violet,
      kind: ExpenseKind.monthly,
    ),
    ExpenseCategory(
      id: 5,
      name: 'Salary',
      icon: Icons.groups_rounded,
      color: AppColors.secondary,
      kind: ExpenseKind.monthly,
    ),
    ExpenseCategory(
      id: 6,
      name: 'Electricity',
      icon: Icons.bolt_rounded,
      color: AppColors.danger,
      kind: ExpenseKind.monthly,
    ),
  ];

  static final List<Expense> expenses = <Expense>[
    Expense(
      id: 1,
      restaurantId: restaurantId,
      name: 'Hilib & Digaag',
      amount: 95000,
      categoryId: 1,
      categoryName: 'Food Supplies',
      method: PaymentMethod.cash,
      date: _now,
      kind: ExpenseKind.daily,
      createdBy: 'Axmed Xasan',
    ),
    Expense(
      id: 2,
      restaurantId: restaurantId,
      name: 'Gaadiid',
      amount: 25000,
      categoryId: 3,
      categoryName: 'Transport',
      method: PaymentMethod.cash,
      date: _now,
      kind: ExpenseKind.daily,
      createdBy: 'Faadumo Cali',
    ),
    Expense(
      id: 3,
      restaurantId: restaurantId,
      name: 'Nadaafad',
      amount: 30000,
      categoryId: 2,
      categoryName: 'Cleaning',
      method: PaymentMethod.zaad,
      date: _now,
      kind: ExpenseKind.daily,
      createdBy: 'Faadumo Cali',
    ),
    Expense(
      id: 4,
      restaurantId: restaurantId,
      name: 'Khudaar',
      amount: 30000,
      categoryId: 1,
      categoryName: 'Food Supplies',
      method: PaymentMethod.cash,
      date: _now,
      kind: ExpenseKind.daily,
      createdBy: 'Axmed Xasan',
    ),
    Expense(
      id: 5,
      restaurantId: restaurantId,
      name: 'Kirada Bishii',
      amount: 600000,
      categoryId: 4,
      categoryName: 'Rent',
      method: PaymentMethod.bank,
      date: _now.subtract(const Duration(days: 6)),
      kind: ExpenseKind.monthly,
      recurring: true,
      createdBy: 'Axmed Xasan',
    ),
    Expense(
      id: 6,
      restaurantId: restaurantId,
      name: 'Mushaharka Shaqaalaha',
      amount: 450000,
      categoryId: 5,
      categoryName: 'Salary',
      method: PaymentMethod.bank,
      date: _now.subtract(const Duration(days: 6)),
      kind: ExpenseKind.monthly,
      recurring: true,
      createdBy: 'Axmed Xasan',
    ),
    Expense(
      id: 7,
      restaurantId: restaurantId,
      name: 'Koronto',
      amount: 120000,
      categoryId: 6,
      categoryName: 'Electricity',
      method: PaymentMethod.edahab,
      date: _now.subtract(const Duration(days: 4)),
      kind: ExpenseKind.monthly,
      recurring: true,
      createdBy: 'Faadumo Cali',
    ),
  ];

  // -------------------------------------------------------------- accounts

  static const List<Account> accounts = <Account>[
    Account(
      id: 1,
      restaurantId: restaurantId,
      method: PaymentMethod.cash,
      balance: 1250000,
      moneyIn: 450000,
      moneyOut: 150000,
    ),
    Account(
      id: 2,
      restaurantId: restaurantId,
      method: PaymentMethod.zaad,
      balance: 2300000,
      moneyIn: 500000,
      moneyOut: 30000,
    ),
    Account(
      id: 3,
      restaurantId: restaurantId,
      method: PaymentMethod.edahab,
      balance: 890000,
      moneyIn: 200000,
      moneyOut: 120000,
    ),
    Account(
      id: 4,
      restaurantId: restaurantId,
      method: PaymentMethod.bank,
      balance: 4500000,
      moneyIn: 100000,
      moneyOut: 0,
    ),
  ];

  // ------------------------------------------------------------- analytics

  static const double todaysSales = 1250000;
  static const int todaysOrders = 48;
  static const double todaysExpenses = 180000;
  static const double todaysNetProfit = 720000;

  static const KpiValue kpiSales = KpiValue(
    value: todaysSales,
    deltaPercent: 12.5,
  );
  static const KpiValue kpiOrders = KpiValue(value: 48, deltaPercent: 8.3);
  static const KpiValue kpiExpenses = KpiValue(
    value: todaysExpenses,
    deltaPercent: -3.2,
  );
  static const KpiValue kpiProfit = KpiValue(
    value: todaysNetProfit,
    deltaPercent: 15.7,
  );

  /// Monday-first week ending today, summing to 8,750,000.
  static List<SeriesPoint> weeklySales() {
    const List<double> values = <double>[
      950000,
      1120000,
      880000,
      1340000,
      1560000,
      1650000,
      1250000,
    ];
    final DateTime now = _now;
    final DateTime monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    return List<SeriesPoint>.generate(7, (int i) {
      final DateTime d = monday.add(Duration(days: i));
      return SeriesPoint(label: '', value: values[i], date: d);
    });
  }

  static const List<double> lastWeekSales = <double>[
    820000,
    940000,
    910000,
    1080000,
    1290000,
    1420000,
    1120000,
  ];

  static List<SeriesPoint> salesByHour() {
    const List<double> values = <double>[
      40000,
      65000,
      90000,
      180000,
      240000,
      195000,
      120000,
      95000,
      130000,
      210000,
      285000,
      240000,
      160000,
      85000,
      40000,
    ];
    return List<SeriesPoint>.generate(values.length, (int i) {
      final int hour = 8 + i;
      return SeriesPoint(
        label: '${hour.toString().padLeft(2, '0')}:00',
        value: values[i],
      );
    });
  }

  static const List<RankedItem> topItemsToday = <RankedItem>[
    RankedItem(
      itemId: 1,
      name: 'Chicken Burger',
      quantity: 45,
      revenue: 1575000,
      emoji: '🍔',
    ),
    RankedItem(
      itemId: 4,
      name: 'Chicken Pizza',
      quantity: 32,
      revenue: 1440000,
      emoji: '🍕',
    ),
    RankedItem(
      itemId: 10,
      name: 'Fresh Juice',
      quantity: 22,
      revenue: 440000,
      emoji: '🧃',
    ),
    RankedItem(
      itemId: 2,
      name: 'Beef Burger',
      quantity: 18,
      revenue: 720000,
      emoji: '🍔',
    ),
    RankedItem(
      itemId: 16,
      name: 'French Fries',
      quantity: 16,
      revenue: 240000,
      emoji: '🍟',
    ),
  ];

  static const List<RankedItem> topItemsPeriod = <RankedItem>[
    RankedItem(
      itemId: 1,
      name: 'Chicken Burger',
      quantity: 120,
      revenue: 4200000,
      emoji: '🍔',
    ),
    RankedItem(
      itemId: 4,
      name: 'Chicken Pizza',
      quantity: 96,
      revenue: 4320000,
      emoji: '🍕',
    ),
    RankedItem(
      itemId: 7,
      name: 'Digaag Duban',
      quantity: 74,
      revenue: 4440000,
      emoji: '🍗',
    ),
    RankedItem(
      itemId: 10,
      name: 'Fresh Juice',
      quantity: 68,
      revenue: 1360000,
      emoji: '🧃',
    ),
    RankedItem(
      itemId: 16,
      name: 'French Fries',
      quantity: 61,
      revenue: 915000,
      emoji: '🍟',
    ),
  ];

  static const List<RankedItem> lowSellingPeriod = <RankedItem>[
    RankedItem(
      itemId: 15,
      name: 'Ice Cream',
      quantity: 4,
      revenue: 60000,
      emoji: '🍨',
    ),
    RankedItem(
      itemId: 13,
      name: 'Water',
      quantity: 7,
      revenue: 35000,
      emoji: '💧',
    ),
    RankedItem(
      itemId: 17,
      name: 'Salad',
      quantity: 9,
      revenue: 108000,
      emoji: '🥗',
    ),
  ];

  static const List<BreakdownSlice> categoryBreakdown = <BreakdownSlice>[
    BreakdownSlice(label: 'Burgers', value: 40, color: AppColors.primary),
    BreakdownSlice(label: 'Pizzas', value: 30, color: AppColors.secondary),
    BreakdownSlice(label: 'Drinks', value: 15, color: AppColors.info),
    BreakdownSlice(label: 'Desserts', value: 10, color: AppColors.violet),
    BreakdownSlice(label: 'Others', value: 5, color: AppColors.success),
  ];

  static const List<BreakdownSlice> paymentBreakdown = <BreakdownSlice>[
    BreakdownSlice(
      label: 'Cash',
      value: 3150000,
      color: AppColors.success,
      count: 118,
    ),
    BreakdownSlice(
      label: 'Zaad',
      value: 3500000,
      color: AppColors.info,
      count: 126,
    ),
    BreakdownSlice(
      label: 'eDahab',
      value: 1400000,
      color: AppColors.secondary,
      count: 52,
    ),
    BreakdownSlice(
      label: 'Bank',
      value: 700000,
      color: AppColors.violet,
      count: 24,
    ),
  ];

  static const List<BreakdownSlice> waiterBreakdown = <BreakdownSlice>[
    BreakdownSlice(
      label: 'Abdullahi',
      value: 3120000,
      color: AppColors.primary,
      count: 112,
    ),
    BreakdownSlice(
      label: 'Hamze',
      value: 2480000,
      color: AppColors.secondary,
      count: 96,
    ),
    BreakdownSlice(
      label: 'Omar',
      value: 1950000,
      color: AppColors.info,
      count: 74,
    ),
    BreakdownSlice(
      label: 'Faadumo',
      value: 1200000,
      color: AppColors.violet,
      count: 38,
    ),
  ];

  // Period totals for the Reports screen (18–24 of the current month).
  static const KpiValue periodSales = KpiValue(
    value: 8750000,
    deltaPercent: 18.6,
  );
  static const KpiValue periodOrders = KpiValue(value: 320, deltaPercent: 14.2);
  static const KpiValue periodExpenses = KpiValue(
    value: 1250000,
    deltaPercent: -4.5,
  );
  static const KpiValue periodProfit = KpiValue(
    value: 7500000,
    deltaPercent: 22.8,
  );

  static const double periodDiscounts = 145000;
  static const double periodTax = 0;
  static const double periodPackaging = 385000;
  static const int periodCancelled = 11;
  static const int periodCompleted = 296;
  static const int periodDrafts = 13;
  static const int periodDineIn = 194;
  static const int periodTakeaway = 126;
}
