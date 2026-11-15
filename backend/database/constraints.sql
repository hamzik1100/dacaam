-- CHECK constraints that not every MySQL/MariaDB build will accept.
--
-- `bin/migrate.php` applies each one on its own and reports what happened.
-- A refusal is not a failure: every rule below is also enforced in the API,
-- with tests, and these exist to make the database refuse a bad row even if
-- something one day writes to it directly.
--
-- Known: MariaDB 11.8 rejects a CHECK that references `orders.table_id`
-- (error 1901, "Function or expression 'table_id' cannot be used in the CHECK
-- clause"), because that column is the target of a FOREIGN KEY with
-- ON DELETE SET NULL. MariaDB 10.4 and MySQL 8 accept the same statement.
--
-- Single-column checks — price > 0, amount >= 0, quantity > 0 — are in
-- schema.sql, because every supported engine takes those.

-- Takeaway never holds a table. Dropping the table on a takeaway order is
-- done in OrderController; this stops any other writer getting it wrong.
ALTER TABLE `orders`
  ADD CONSTRAINT `chk_orders_takeaway_has_no_table`
  CHECK (`order_type` <> 'takeaway' OR `table_id` IS NULL);

-- A cancelled order must say why. Without this a cancellation can erase a
-- sale leaving nothing to answer for it.
ALTER TABLE `orders`
  ADD CONSTRAINT `chk_orders_cancel_reason`
  CHECK (`status` <> 'cancelled' OR (`cancel_reason` IS NOT NULL AND `cancel_reason` <> ''));
