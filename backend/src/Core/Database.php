<?php

declare(strict_types=1);

namespace Dacaam\Core;

use PDO;
use PDOStatement;
use RuntimeException;
use Throwable;

/**
 * Thin PDO wrapper.
 *
 * Every query in the application goes through here with bound parameters —
 * there is no string interpolation of user input anywhere in the codebase.
 */
final class Database
{
    private static ?PDO $pdo = null;

    public static function connection(): PDO
    {
        if (self::$pdo instanceof PDO) {
            return self::$pdo;
        }

        $dsn = sprintf(
            'mysql:host=%s;port=%d;dbname=%s;charset=%s',
            (string) Config::get('db.host'),
            (int) Config::get('db.port'),
            (string) Config::get('db.database'),
            (string) Config::get('db.charset'),
        );

        try {
            self::$pdo = new PDO(
                $dsn,
                (string) Config::get('db.username'),
                (string) Config::get('db.password'),
                [
                    PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                    // Real prepared statements, not client-side emulation:
                    // keeps types intact and removes a class of injection risk.
                    PDO::ATTR_EMULATE_PREPARES   => false,
                    PDO::ATTR_STRINGIFY_FETCHES  => false,
                ],
            );
        } catch (Throwable $e) {
            throw new RuntimeException(
                'Database connection failed: ' . $e->getMessage(),
                previous: $e,
            );
        }

        // MySQL stamps every DEFAULT CURRENT_TIMESTAMP with its own session
        // zone, which on a shared host is UTC, while PHP runs on the
        // restaurant's zone. Left alone the two disagree by the offset, and an
        // order placed a moment ago reads as three hours old.
        //
        // The offset is derived from the same config value PHP uses, so they
        // cannot drift apart. A numeric offset rather than the zone name
        // because MySQL's named-timezone tables are frequently not loaded on
        // shared hosting, and 'Africa/Mogadishu' would silently do nothing.
        $offset = (new \DateTimeImmutable(
            'now',
            new \DateTimeZone((string) Config::get('app.timezone')),
        ))->format('P');

        self::$pdo->exec(sprintf("SET time_zone = '%s'", $offset));

        return self::$pdo;
    }

    /** @param array<string|int,mixed> $bindings */
    public static function run(string $sql, array $bindings = []): PDOStatement
    {
        $statement = self::connection()->prepare($sql);
        $statement->execute($bindings);

        return $statement;
    }

    /**
     * @param  array<string|int,mixed> $bindings
     * @return list<array<string,mixed>>
     */
    public static function select(string $sql, array $bindings = []): array
    {
        /** @var list<array<string,mixed>> $rows */
        $rows = self::run($sql, $bindings)->fetchAll();

        return $rows;
    }

    /**
     * @param  array<string|int,mixed> $bindings
     * @return array<string,mixed>|null
     */
    public static function selectOne(string $sql, array $bindings = []): ?array
    {
        /** @var array<string,mixed>|false $row */
        $row = self::run($sql, $bindings)->fetch();

        return $row === false ? null : $row;
    }

    /** @param array<string|int,mixed> $bindings */
    public static function scalar(string $sql, array $bindings = []): mixed
    {
        return self::run($sql, $bindings)->fetchColumn();
    }

    /**
     * @param  array<string,mixed> $data
     * @return int Inserted id
     */
    public static function insert(string $table, array $data): int
    {
        $columns = array_keys($data);
        $sql = sprintf(
            'INSERT INTO `%s` (%s) VALUES (%s)',
            $table,
            implode(', ', array_map(static fn (string $c): string => "`$c`", $columns)),
            implode(', ', array_map(static fn (string $c): string => ":$c", $columns)),
        );

        self::run($sql, $data);

        return (int) self::connection()->lastInsertId();
    }

    /**
     * Updates a row, always scoped by restaurant so a stray id cannot reach
     * another tenant's data.
     *
     * @param  array<string,mixed> $data
     */
    public static function updateScoped(
        string $table,
        array $data,
        int $id,
        int $restaurantId,
    ): int {
        if ($data === []) {
            return 0;
        }

        $assignments = implode(
            ', ',
            array_map(static fn (string $c): string => "`$c` = :$c", array_keys($data)),
        );

        $sql = sprintf(
            'UPDATE `%s` SET %s WHERE `id` = :__id AND `restaurant_id` = :__rid',
            $table,
            $assignments,
        );

        return self::run($sql, $data + ['__id' => $id, '__rid' => $restaurantId])->rowCount();
    }

    /**
     * Runs a closure inside a transaction, rolling back on any throwable.
     *
     * @template T
     * @param  callable():T $work
     * @return T
     */
    public static function transaction(callable $work): mixed
    {
        $pdo = self::connection();
        $pdo->beginTransaction();

        try {
            $result = $work();
            $pdo->commit();

            return $result;
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $e;
        }
    }
}
