-- DACAAM seed data — LOCAL DEVELOPMENT ONLY.
--
-- Two tenants (HAMZE, WARFA) with deliberately different menus, prices and
-- staff, so tenant isolation is something you can observe rather than assume:
-- if a HAMZE token ever returns "Camel Suqaar", isolation is broken.
--
-- Every seeded user's password is `admin123`. Never ship this file to a
-- production database.
--
-- Idempotent: re-running replaces the seeded rows without touching schema.

-- No USE: see the note at the top of schema.sql. The database is chosen by
-- `bin/migrate.php`, or by whichever one you have open in phpMyAdmin.

SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE `account_transactions`;
TRUNCATE TABLE `accounts`;
TRUNCATE TABLE `api_tokens`;
TRUNCATE TABLE `auth_challenges`;
TRUNCATE TABLE `password_resets`;
TRUNCATE TABLE `two_factor_recovery_codes`;
TRUNCATE TABLE `two_factor_used_codes`;
TRUNCATE TABLE `audit_logs`;
TRUNCATE TABLE `draft_order_items`;
TRUNCATE TABLE `draft_orders`;
TRUNCATE TABLE `expenses`;
TRUNCATE TABLE `expense_categories`;
TRUNCATE TABLE `login_attempts`;
TRUNCATE TABLE `order_items`;
TRUNCATE TABLE `order_payments`;
TRUNCATE TABLE `orders`;
TRUNCATE TABLE `menu_items`;
TRUNCATE TABLE `categories`;
TRUNCATE TABLE `tables`;
TRUNCATE TABLE `user_permissions`;
TRUNCATE TABLE `user_roles`;
TRUNCATE TABLE `role_permissions`;
TRUNCATE TABLE `roles`;
TRUNCATE TABLE `users`;
TRUNCATE TABLE `restaurant_settings`;
TRUNCATE TABLE `subscription_payments`;
TRUNCATE TABLE `subscriptions`;
TRUNCATE TABLE `platform_audit_logs`;
TRUNCATE TABLE `super_admins`;
TRUNCATE TABLE `restaurants`;
TRUNCATE TABLE `system_settings`;
SET FOREIGN_KEY_CHECKS = 1;

-- ================================================= permission catalogue
--
-- Deliberately not here. It lives in permissions.sql, which migrate.php
-- applies on every run — including production, where seed.sql must never be
-- run because it TRUNCATEs.
--
-- This file used to TRUNCATE `permissions` and insert its own list. Because
-- seed.sql runs AFTER permissions.sql, that quietly replaced the real
-- catalogue with a stale copy: a freshly seeded database came up missing the
-- five customers.* permissions, so the admin could not open the customer
-- screens at all and the failure looked like a bug in the feature.
--
-- The role grants below still work: permissions.sql has already populated
-- the table by the time this runs.

-- ============================================================== tenants

INSERT INTO `restaurants` (`id`,`slug`,`name`,`phone`,`address`,`logo_emoji`,`status`) VALUES
  (1,'HAMZE','Hamze Restaurant','063 4567890','Jigjiga Yar, Hargeysa','🍔','active'),
  (2,'WARFA','Warfa Restaurant','063 7778899','Xero Awr, Hargeysa','🥘','active');

INSERT INTO `subscriptions` (`id`,`restaurant_id`,`plan`,`status`,`starts_on`,`ends_on`,`amount`) VALUES
  (1,1,'standard','active', DATE_SUB(CURDATE(), INTERVAL 60 DAY), DATE_ADD(CURDATE(), INTERVAL 305 DAY), 1200000.00),
  (2,2,'trial','trial',     DATE_SUB(CURDATE(), INTERVAL 5 DAY),  DATE_ADD(CURDATE(), INTERVAL 25 DAY),  0.00);

INSERT INTO `subscription_payments`
  (`subscription_id`,`restaurant_id`,`amount`,`method`,`reference`,`paid_on`) VALUES
  (1,1,1200000.00,'bank','SUB-2026-001', DATE_SUB(CURDATE(), INTERVAL 60 DAY));

-- Platform login for local development only: super@dacaam.test / admin123
INSERT INTO `super_admins` (`id`,`name`,`email`,`password_hash`) VALUES
  (1,'Platform Admin','super@dacaam.test','$2y$10$Gwi/1LoOdnlwhksDN7B7B..njadcVnXjkIsUsFI6cd0kb8e2Njazu');

INSERT INTO `restaurant_settings`
  (`restaurant_id`,`language`,`currency_prefix`,`tax_rate`,`tax_enabled`,`packaging_fee_enabled`,
   `packaging_fee`,`require_table_for_dine_in`,`password_min_length`,`password_require_number`) VALUES
  (1,'so','SLSH',5.000,0,1,5000.00,1,6,0),
  -- WARFA runs with tax on and a stricter password policy, to prove both are
  -- settings-driven rather than hardcoded.
  (2,'so','SLSH',5.000,1,1,3000.00,0,8,1);

-- ================================================================ roles

INSERT INTO `roles` (`id`,`restaurant_id`,`code`,`name`,`is_system`) VALUES
  (1,1,'admin','Maamule',1),
  (2,1,'operator','Hawlwadeen',1),
  (3,1,'waiter','Adeege',1),
  (4,2,'admin','Maamule',1),
  (5,2,'operator','Hawlwadeen',1),
  (6,2,'waiter','Adeege',1);

-- Admin: everything.
INSERT INTO `role_permissions` (`role_id`,`permission_id`)
SELECT r.id, p.id FROM `roles` r CROSS JOIN `permissions` p WHERE r.code = 'admin';

-- Operator: day-to-day operations, no user management or security settings.
INSERT INTO `role_permissions` (`role_id`,`permission_id`)
SELECT r.id, p.id FROM `roles` r JOIN `permissions` p
  ON p.code IN (
    'orders.view','orders.create','orders.edit','orders.cancel',
    'menu.view','menu.create','menu.edit',
    'expenses.view','expenses.create',
    'reports.view',
    'tables.view','tables.manage',
    'accounts.view',
    'settings.view'
  )
WHERE r.code = 'operator';

-- Waiter: take orders, read the menu, see tables. Nothing financial.
INSERT INTO `role_permissions` (`role_id`,`permission_id`)
SELECT r.id, p.id FROM `roles` r JOIN `permissions` p
  ON p.code IN ('orders.view','orders.create','menu.view','tables.view')
WHERE r.code = 'waiter';

-- ================================================================ users
-- password for all seeded users: admin123

INSERT INTO `users` (`id`,`restaurant_id`,`name`,`phone`,`password_hash`) VALUES
  (1,1,'Axmed Xasan','0634567890','$2y$10$Gwi/1LoOdnlwhksDN7B7B..njadcVnXjkIsUsFI6cd0kb8e2Njazu'),
  (2,1,'Faadumo Cali','0631122334','$2y$10$Gwi/1LoOdnlwhksDN7B7B..njadcVnXjkIsUsFI6cd0kb8e2Njazu'),
  (3,1,'Abdullahi Warsame','0632233445','$2y$10$Gwi/1LoOdnlwhksDN7B7B..njadcVnXjkIsUsFI6cd0kb8e2Njazu'),
  (4,1,'Omar Jaamac','0633344556','$2y$10$Gwi/1LoOdnlwhksDN7B7B..njadcVnXjkIsUsFI6cd0kb8e2Njazu'),
  (5,1,'Hamze Cabdi','0634455667','$2y$10$Gwi/1LoOdnlwhksDN7B7B..njadcVnXjkIsUsFI6cd0kb8e2Njazu'),
  (6,2,'Warfa Diiriye','0637778899','$2y$10$Gwi/1LoOdnlwhksDN7B7B..njadcVnXjkIsUsFI6cd0kb8e2Njazu'),
  (7,2,'Nasteexo Yuusuf','0635556677','$2y$10$Gwi/1LoOdnlwhksDN7B7B..njadcVnXjkIsUsFI6cd0kb8e2Njazu');

INSERT INTO `user_roles` (`user_id`,`role_id`) VALUES
  (1,1),(2,2),(3,3),(4,3),(5,3),
  (6,4),(7,6);

-- =========================================================== HAMZE menu

INSERT INTO `categories` (`id`,`restaurant_id`,`name`,`description`,`emoji`,`color`,`sort_order`) VALUES
  (1,1,'Burgers','Beef and chicken burgers','🍔','#F97316',1),
  (2,1,'Pizzas','Stone baked pizzas','🍕','#F59E0B',2),
  (3,1,'Chicken','Grilled and fried chicken','🍗','#14B8A6',3),
  (4,1,'Drinks','Juices, tea and soft drinks','🥤','#3B82F6',4),
  (5,1,'Desserts','Cakes and ice cream','🍰','#8B5CF6',5),
  (6,1,'Sides','Fries, salad and rice','🍟','#10B981',6);

INSERT INTO `menu_items`
  (`id`,`restaurant_id`,`category_id`,`name`,`description`,`price`,`emoji`,`is_available`,`apply_packaging_fee`,`sort_order`) VALUES
  (1,1,1,'Chicken Burger','Chicken burger with fries',35000,'🍔',1,1,1),
  (2,1,1,'Beef Burger','Grilled beef patty, cheddar, house sauce',40000,'🍔',1,1,2),
  (3,1,1,'Cheese Burger','Double cheese with caramelised onion',38000,'🧀',1,1,3),
  (4,1,2,'Chicken Pizza','Chicken, mozzarella, peppers',45000,'🍕',1,1,4),
  (5,1,2,'Margherita Pizza','Tomato, basil, fresh mozzarella',50000,'🍕',1,1,5),
  (6,1,2,'Beef Pizza','Minced beef, onion, olives',55000,'🍕',1,1,6),
  (7,1,3,'Digaag Duban','Half grilled chicken with rice',60000,'🍗',1,1,7),
  (8,1,3,'Chicken Wings','Eight spicy wings',30000,'🍗',1,1,8),
  (9,1,3,'Chicken Shawarma','Shawarma wrap with garlic sauce',25000,'🌯',1,1,9),
  (10,1,4,'Fresh Juice','Mango, avocado or mixed',20000,'🧃',1,1,10),
  (11,1,4,'Shaah Somali','Spiced Somali tea',8000,'☕',1,0,11),
  (12,1,4,'Soft Drink','Chilled 300ml bottle',10000,'🥤',1,0,12),
  (13,1,4,'Water','500ml mineral water',5000,'💧',1,0,13),
  (14,1,5,'Chocolate Cake','Rich chocolate sponge',25000,'🍰',1,1,14),
  (15,1,5,'Ice Cream','Two scoops, choice of flavour',15000,'🍨',0,1,15),
  (16,1,6,'French Fries','Crispy salted fries',15000,'🍟',1,1,16),
  (17,1,6,'Salad','Garden salad with lemon dressing',12000,'🥗',1,1,17),
  (18,1,6,'Bariis','Somali spiced rice',18000,'🍚',1,1,18);

INSERT INTO `tables` (`id`,`restaurant_id`,`table_number`,`name`,`capacity`,`status`,`is_active`) VALUES
  (1,1,1,'',4,'available',1),
  (2,1,2,'',2,'available',1),
  (3,1,3,'',4,'available',1),
  (4,1,4,'',6,'reserved',1),
  (5,1,5,'',2,'available',1),
  (6,1,6,'',8,'available',1),
  (7,1,7,'',4,'available',1),
  (8,1,8,'',4,'available',1),
  (9,1,9,'',2,'disabled',0),
  (10,1,10,'',6,'available',1),
  (11,1,11,'',4,'reserved',1),
  (12,1,12,'VIP Hall',10,'available',1);

-- =========================================================== WARFA menu
-- Deliberately different food and prices — the isolation canary.

INSERT INTO `categories` (`id`,`restaurant_id`,`name`,`description`,`emoji`,`color`,`sort_order`) VALUES
  (20,2,'Suqaar','Traditional Somali suqaar','🥘','#F97316',1),
  (21,2,'Baasto','Pasta dishes','🍝','#F59E0B',2),
  (22,2,'Cabitaan','Drinks','🍵','#3B82F6',3);

INSERT INTO `menu_items`
  (`id`,`restaurant_id`,`category_id`,`name`,`description`,`price`,`emoji`,`is_available`,`apply_packaging_fee`,`sort_order`) VALUES
  (30,2,20,'Camel Suqaar','Camel meat suqaar with anjeero',70000,'🥘',1,1,1),
  (31,2,20,'Goat Suqaar','Goat suqaar with rice',65000,'🥘',1,1,2),
  (32,2,21,'Baasto Hilib','Pasta with beef sauce',42000,'🍝',1,1,3),
  (33,2,22,'Shaah Cadeys','Milk tea',9000,'🍵',1,0,4);

INSERT INTO `tables` (`id`,`restaurant_id`,`table_number`,`name`,`capacity`,`status`,`is_active`) VALUES
  (40,2,1,'',4,'available',1),
  (41,2,2,'',4,'available',1),
  (42,2,3,'',6,'available',1);

-- ============================================================ accounts

INSERT INTO `accounts` (`id`,`restaurant_id`,`method`,`name`,`balance`) VALUES
  (1,1,'cash','Cash',1250000.00),
  (2,1,'zaad','Zaad',2300000.00),
  (3,1,'edahab','eDahab',890000.00),
  (4,1,'bank','Bank',4500000.00),
  (5,2,'cash','Cash',320000.00),
  (6,2,'zaad','Zaad',150000.00),
  (7,2,'edahab','eDahab',0.00),
  (8,2,'bank','Bank',0.00);

-- ==================================================== expense categories

INSERT INTO `expense_categories` (`id`,`restaurant_id`,`name`,`kind`,`icon`,`color`) VALUES
  (1,1,'Food Supplies','daily','local_grocery_store','#F97316'),
  (2,1,'Cleaning','daily','cleaning_services','#3B82F6'),
  (3,1,'Transport','daily','local_shipping','#14B8A6'),
  (4,1,'Rent','monthly','home_work','#8B5CF6'),
  (5,1,'Salary','monthly','groups','#F59E0B'),
  (6,1,'Electricity','monthly','bolt','#EF4444'),
  (7,2,'Food Supplies','daily','local_grocery_store','#F97316'),
  (8,2,'Rent','monthly','home_work','#8B5CF6');

INSERT INTO `expenses`
  (`restaurant_id`,`expense_category_id`,`name`,`amount`,`kind`,`method`,`expense_date`,`is_recurring`,`created_by`) VALUES
  (1,1,'Hilib & Digaag',95000,'daily','cash',CURDATE(),0,1),
  (1,3,'Gaadiid',25000,'daily','cash',CURDATE(),0,2),
  (1,2,'Nadaafad',30000,'daily','zaad',CURDATE(),0,2),
  (1,1,'Khudaar',30000,'daily','cash',CURDATE(),0,1),
  (1,4,'Kirada Bishii',600000,'monthly','bank',DATE_SUB(CURDATE(), INTERVAL 6 DAY),1,1),
  (1,5,'Mushaharka Shaqaalaha',450000,'monthly','bank',DATE_SUB(CURDATE(), INTERVAL 6 DAY),1,1),
  (1,6,'Koronto',120000,'monthly','edahab',DATE_SUB(CURDATE(), INTERVAL 4 DAY),1,2),
  (2,7,'Hilib Geel',180000,'daily','cash',CURDATE(),0,6),
  (2,8,'Kiro',300000,'monthly','bank',DATE_SUB(CURDATE(), INTERVAL 3 DAY),1,6);

-- =============================================================== orders
-- Totals are stated explicitly here because this is a fixture; the API always
-- recomputes them from menu prices and settings when creating an order.

INSERT INTO `orders`
  (`id`,`restaurant_id`,`order_number`,`order_type`,`status`,`table_id`,`waiter_id`,`waiter_name`,
   `customer_name`,`customer_phone`,`guests`,`subtotal`,`discount`,`tax_rate`,`tax_amount`,
   `packaging_fee`,`total`,`cancel_reason`,`created_by`,`created_at`) VALUES
  (1,1,1025,'dine_in','preparing',3,3,'Abdullahi','','',3,85000,0,0,0,0,85000,NULL,3,DATE_SUB(NOW(), INTERVAL 2 MINUTE)),
  (2,1,1024,'takeaway','ready',NULL,5,'Hamze','Maxamed','0637788990',0,37000,0,0,0,5000,42000,NULL,5,DATE_SUB(NOW(), INTERVAL 10 MINUTE)),
  (3,1,1023,'dine_in','preparing',6,4,'Omar','','',6,120000,0,0,0,0,120000,NULL,4,DATE_SUB(NOW(), INTERVAL 15 MINUTE)),
  (4,1,1022,'takeaway','completed',NULL,5,'Hamze','','',0,30000,0,0,0,5000,35000,NULL,5,DATE_SUB(NOW(), INTERVAL 20 MINUTE)),
  (5,1,1021,'dine_in','completed',1,3,'Abdullahi','','',2,65000,0,0,0,0,65000,NULL,3,DATE_SUB(NOW(), INTERVAL 25 MINUTE)),
  (6,1,1020,'dine_in','cancelled',4,4,'Omar','','',2,28000,0,0,0,0,28000,'Macmiilku wuu ka noqday dalabka',4,DATE_SUB(NOW(), INTERVAL 30 MINUTE)),
  (7,1,1019,'takeaway','completed',NULL,5,'Hamze','Khadra','',0,95000,0,0,0,5000,100000,NULL,5,DATE_SUB(NOW(), INTERVAL 52 MINUTE)),
  (8,1,1018,'dine_in','completed',8,3,'Abdullahi','','',4,95000,5000,0,0,0,90000,NULL,3,DATE_SUB(NOW(), INTERVAL 75 MINUTE)),
  (9,1,1017,'dine_in','pending',10,4,'Omar','','',5,96000,0,0,0,0,96000,NULL,4,DATE_SUB(NOW(), INTERVAL 96 MINUTE)),
  (10,1,1016,'takeaway','completed',NULL,5,'Hamze','','',0,78000,0,0,0,5000,83000,NULL,5,DATE_SUB(NOW(), INTERVAL 192 MINUTE)),
  (11,1,1015,'dine_in','completed',2,3,'Abdullahi','','',2,86000,0,0,0,0,86000,NULL,3,DATE_SUB(NOW(), INTERVAL 245 MINUTE)),
  (12,1,1013,'dine_in','completed',12,2,'Faadumo','','',9,314000,20000,0,0,0,294000,NULL,2,DATE_SUB(NOW(), INTERVAL 1560 MINUTE)),
  -- WARFA order: tax enabled at 5%, packaging 3,000.
  (13,2,501,'takeaway','completed',NULL,7,'Nasteexo','Cali','0631112223',0,70000,0,5.000,3500,3000,76500,NULL,7,DATE_SUB(NOW(), INTERVAL 40 MINUTE));

INSERT INTO `order_items`
  (`restaurant_id`,`order_id`,`menu_item_id`,`item_name`,`unit_price`,`quantity`,`line_total`,`emoji`,`apply_packaging_fee`) VALUES
  (1,1,1,'Chicken Burger',35000,1,35000,'🍔',1),
  (1,1,16,'French Fries',15000,2,30000,'🍟',1),
  (1,1,10,'Fresh Juice',20000,1,20000,'🧃',1),
  (1,2,9,'Chicken Shawarma',25000,1,25000,'🌯',1),
  (1,2,17,'Salad',12000,1,12000,'🥗',1),
  (1,3,6,'Beef Pizza',55000,1,55000,'🍕',1),
  (1,3,4,'Chicken Pizza',45000,1,45000,'🍕',1),
  (1,3,10,'Fresh Juice',20000,1,20000,'🧃',1),
  (1,4,8,'Chicken Wings',30000,1,30000,'🍗',1),
  (1,5,7,'Digaag Duban',60000,1,60000,'🍗',1),
  (1,5,13,'Water',5000,1,5000,'💧',0),
  (1,6,10,'Fresh Juice',20000,1,20000,'🧃',1),
  (1,6,11,'Shaah Somali',8000,1,8000,'☕',0),
  (1,7,2,'Beef Burger',40000,2,80000,'🍔',1),
  (1,7,16,'French Fries',15000,1,15000,'🍟',1),
  (1,8,5,'Margherita Pizza',50000,1,50000,'🍕',1),
  (1,8,12,'Soft Drink',10000,2,20000,'🥤',0),
  (1,8,14,'Chocolate Cake',25000,1,25000,'🍰',1),
  (1,9,18,'Bariis',18000,2,36000,'🍚',1),
  (1,9,7,'Digaag Duban',60000,1,60000,'🍗',1),
  (1,10,3,'Cheese Burger',38000,1,38000,'🧀',1),
  (1,10,10,'Fresh Juice',20000,2,40000,'🧃',1),
  (1,11,1,'Chicken Burger',35000,2,70000,'🍔',1),
  (1,11,11,'Shaah Somali',8000,2,16000,'☕',0),
  (1,12,7,'Digaag Duban',60000,3,180000,'🍗',1),
  (1,12,18,'Bariis',18000,3,54000,'🍚',1),
  (1,12,10,'Fresh Juice',20000,4,80000,'🧃',1),
  (2,13,30,'Camel Suqaar',70000,1,70000,'🥘',1);

INSERT INTO `order_payments` (`restaurant_id`,`order_id`,`method`,`amount`,`reference`,`received_by`,`created_at`) VALUES
  (1,4,'zaad',35000,'ZD-88213',5,DATE_SUB(NOW(), INTERVAL 19 MINUTE)),
  (1,5,'cash',65000,'',3,DATE_SUB(NOW(), INTERVAL 24 MINUTE)),
  (1,7,'edahab',100000,'ED-44120',5,DATE_SUB(NOW(), INTERVAL 51 MINUTE)),
  (1,8,'cash',90000,'',3,DATE_SUB(NOW(), INTERVAL 74 MINUTE)),
  (1,10,'zaad',83000,'ZD-88190',5,DATE_SUB(NOW(), INTERVAL 191 MINUTE)),
  (1,11,'cash',86000,'',3,DATE_SUB(NOW(), INTERVAL 244 MINUTE)),
  (1,12,'bank',294000,'BK-2291',2,DATE_SUB(NOW(), INTERVAL 1559 MINUTE)),
  (2,13,'zaad',76500,'ZD-99001',7,DATE_SUB(NOW(), INTERVAL 39 MINUTE));

UPDATE `tables` SET `status`='occupied', `current_order_id`=1 WHERE `id`=3;
UPDATE `tables` SET `status`='occupied', `current_order_id`=3 WHERE `id`=6;
UPDATE `tables` SET `status`='occupied', `current_order_id`=9 WHERE `id`=10;

-- =============================================================== drafts

INSERT INTO `draft_orders`
  (`id`,`restaurant_id`,`code`,`customer_name`,`customer_phone`,`order_type`,`table_id`,`waiter_id`,`waiter_name`,
   `packaging_applied`,`status`,`notes`,`created_by`,`created_at`) VALUES
  (1,1,'D-102','Mohamed','0635566778','takeaway',NULL,5,'Hamze',1,'draft','Wuxuu soo qaadan doonaa 19:30',5,DATE_SUB(NOW(), INTERVAL 45 MINUTE)),
  (2,1,'D-101','Saynab','0639988776','dine_in',7,3,'Abdullahi',0,'pending','',3,DATE_SUB(NOW(), INTERVAL 140 MINUTE)),
  (3,1,'D-100','Cabdiraxmaan','','takeaway',NULL,4,'Omar',1,'draft','',4,DATE_SUB(NOW(), INTERVAL 320 MINUTE));

INSERT INTO `draft_order_items`
  (`restaurant_id`,`draft_order_id`,`menu_item_id`,`item_name`,`unit_price`,`quantity`,`line_total`,`emoji`,`apply_packaging_fee`) VALUES
  (1,1,1,'Chicken Burger',35000,2,70000,'🍔',1),
  (1,1,10,'Fresh Juice',20000,2,40000,'🧃',1),
  (1,2,5,'Margherita Pizza',50000,1,50000,'🍕',1),
  (1,2,17,'Salad',12000,2,24000,'🥗',1),
  (1,2,11,'Shaah Somali',8000,3,24000,'☕',0),
  (1,3,8,'Chicken Wings',30000,4,120000,'🍗',1);

-- =========================================================== audit trail
-- Order #1025's timeline, as the Order Details screen renders it.

INSERT INTO `audit_logs`
  (`restaurant_id`,`user_id`,`user_name`,`module`,`action`,`record_id`,`field`,`old_value`,`new_value`,`reason`,`created_at`) VALUES
  (1,3,'Abdullahi Warsame','orders','order_created',1,'',NULL,NULL,NULL,DATE_SUB(NOW(), INTERVAL 2 MINUTE)),
  (1,3,'Abdullahi Warsame','orders','item_added',1,'items',NULL,'French Fries × 1',NULL,DATE_SUB(NOW(), INTERVAL 2 MINUTE)),
  (1,3,'Abdullahi Warsame','orders','quantity_changed',1,'quantity','1','2','Macmiilku wuu kordhiyay',DATE_SUB(NOW(), INTERVAL 1 MINUTE)),
  (1,5,'Hamze Cabdi','orders','order_created',2,'',NULL,NULL,NULL,DATE_SUB(NOW(), INTERVAL 10 MINUTE)),
  (1,5,'Hamze Cabdi','orders','order_status_changed',2,'status','preparing','ready',NULL,DATE_SUB(NOW(), INTERVAL 4 MINUTE)),
  (1,5,'Hamze Cabdi','orders','order_created',4,'',NULL,NULL,NULL,DATE_SUB(NOW(), INTERVAL 20 MINUTE)),
  (1,5,'Hamze Cabdi','orders','payment_added',4,'payment',NULL,'Zaad · 35,000',NULL,DATE_SUB(NOW(), INTERVAL 19 MINUTE)),
  (1,5,'Hamze Cabdi','orders','order_status_changed',4,'status','ready','completed',NULL,DATE_SUB(NOW(), INTERVAL 19 MINUTE)),
  (1,4,'Omar Jaamac','orders','order_created',6,'',NULL,NULL,NULL,DATE_SUB(NOW(), INTERVAL 30 MINUTE)),
  (1,4,'Omar Jaamac','orders','order_status_changed',6,'status','pending','cancelled','Macmiilku wuu ka noqday dalabka',DATE_SUB(NOW(), INTERVAL 27 MINUTE)),
  (1,1,'Axmed Xasan','menu','menu_item_updated',1,'price','30000','35000','Price update',DATE_SUB(NOW(), INTERVAL 3 DAY));

INSERT INTO `system_settings` (`key_name`,`value`) VALUES
  ('app_name','DACAAM'),
  ('api_version','v1'),
  ('default_language','so'),
  ('default_currency','SLSH'),
  -- SMTP is a platform concern, configured by the Super Admin. Blank host
  -- means password reset by email is simply unavailable, which the API
  -- reports honestly rather than pretending to send.
  ('smtp_host',''),
  ('smtp_port','587'),
  ('smtp_encryption','tls'),
  ('smtp_username',''),
  ('smtp_password',''),
  ('smtp_from_email',''),
  ('smtp_from_name','DACAAM');

UPDATE `users` SET `email` = 'admin@hamze.test' WHERE `id` = 1;
UPDATE `users` SET `email` = 'admin@warfa.test' WHERE `id` = 6;
