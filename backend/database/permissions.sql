-- ============================================================================
-- Permission catalogue — reference data, not sample data.
--
-- This used to live only in seed.sql. Deployment tells you never to run
-- seed.sql against production (it TRUNCATEs), so production came up with an
-- EMPTY permissions table. Provisioner::createRoles() grants an admin
-- "everything" with `SELECT id FROM permissions` — against an empty table that
-- is zero rows, so every restaurant created on production had an admin with no
-- permissions at all, and every guarded route answered "Missing permission: x".
--
-- The catalogue is part of the schema's meaning, so it ships with the schema
-- and migrate.php applies it on every run. Everything here is idempotent:
-- re-running it grants nothing twice and removes nothing.
-- ============================================================================

INSERT IGNORE INTO `permissions` (`code`, `module`, `action`) VALUES
  ('orders.view','orders','view'),
  ('orders.create','orders','create'),
  ('orders.edit','orders','edit'),
  ('orders.cancel','orders','cancel'),
  ('orders.delete','orders','delete'),
  ('menu.view','menu','view'),
  ('menu.create','menu','create'),
  ('menu.edit','menu','edit'),
  ('menu.delete','menu','delete'),
  ('expenses.view','expenses','view'),
  ('expenses.create','expenses','create'),
  ('expenses.edit','expenses','edit'),
  ('expenses.delete','expenses','delete'),
  ('reports.view','reports','view'),
  ('reports.export','reports','export'),
  ('users.view','users','view'),
  ('users.create','users','create'),
  ('users.edit','users','edit'),
  ('users.delete','users','delete'),
  ('tables.view','tables','view'),
  ('tables.manage','tables','manage'),
  ('accounts.view','accounts','view'),
  ('accounts.manage','accounts','manage'),
  ('settings.view','settings','view'),
  ('settings.manage','settings','manage'),
  ('audit.view','audit','view'),
  ('customers.view','customers','view'),
  ('customers.create','customers','create'),
  ('customers.edit','customers','edit'),
  ('customers.delete','customers','delete'),
  -- Taking money is not the same right as correcting a spelling. Both used to
  -- be customers.edit, so anyone who could rename a customer could also post
  -- repayments and deposits against them.
  ('customers.payment','customers','payment'),
  -- Deliberately separate from customers.edit. Editing a name is clerical;
  -- moving a balance by hand is the one action that can make a debt disappear
  -- with no sale behind it, so it is granted on its own or not at all.
  ('customers.adjust','customers','adjust');

-- ---------------------------------------------------------------- backfill
--
-- Restaurants provisioned while the catalogue was empty have system roles with
-- no grants. Repair them to the same sets a fresh provision would produce.
--
-- Scoped to `is_system = 1`: a custom role someone built by hand is theirs, and
-- INSERT IGNORE only ever adds, so a permission deliberately removed from a
-- custom role stays removed.

-- Admin: everything.
INSERT IGNORE INTO `role_permissions` (`role_id`, `permission_id`)
SELECT r.`id`, p.`id`
  FROM `roles` r
 CROSS JOIN `permissions` p
 WHERE r.`code` = 'admin' AND r.`is_system` = 1;

-- Operator: day-to-day running, no user management and no destructive deletes.
INSERT IGNORE INTO `role_permissions` (`role_id`, `permission_id`)
SELECT r.`id`, p.`id`
  FROM `roles` r
  JOIN `permissions` p
    ON p.`code` IN (
       'orders.view','orders.create','orders.edit','orders.cancel',
       'menu.view','menu.create','menu.edit',
       'expenses.view','expenses.create',
       'reports.view',
       'tables.view','tables.manage',
       'accounts.view',
       'settings.view',
       -- An operator serves customers on credit and takes their repayments,
       -- but does not get customers.adjust or customers.delete.
       'customers.view','customers.create','customers.edit','customers.payment'
    )
 WHERE r.`code` = 'operator' AND r.`is_system` = 1;

-- Waiter: take orders, read the menu and the floor.
INSERT IGNORE INTO `role_permissions` (`role_id`, `permission_id`)
SELECT r.`id`, p.`id`
  FROM `roles` r
  JOIN `permissions` p
    ON p.`code` IN ('orders.view','orders.create','menu.view','tables.view')
 WHERE r.`code` = 'waiter' AND r.`is_system` = 1;
