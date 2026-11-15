<?php

declare(strict_types=1);

namespace Dacaam\Core;

/**
 * The authenticated caller.
 *
 * `restaurantId` comes from the token record, never from the request. Every
 * query in the application scopes on this value — that single rule is what
 * makes cross-tenant reads impossible rather than merely unlikely.
 */
final class AuthContext
{
    /** @param list<string> $permissions */
    public function __construct(
        public readonly int $userId,
        public readonly int $restaurantId,
        public readonly string $userName,
        public readonly string $restaurantSlug,
        public readonly array $permissions,
        public readonly string $ip = '',
        public readonly string $device = '',
        public readonly int $tokenId = 0,
        /**
         * Set when the subscription has lapsed. The restaurant keeps every
         * read — their history, their reports, their exports — and loses the
         * ability to write. Locking them out of their own records to collect
         * a renewal would be holding the data hostage.
         */
        public readonly bool $readOnly = false,
        public readonly string $readOnlyReason = '',
    ) {
    }

    public function can(string $permission): bool
    {
        return in_array($permission, $this->permissions, true);
    }

    public function require(string $permission): void
    {
        if (!$this->can($permission)) {
            throw ApiException::forbidden(sprintf('Missing permission: %s', $permission));
        }
    }
}
