<?php

declare(strict_types=1);

namespace Dacaam\Core;

/**
 * Per-restaurant password rules.
 *
 * Deliberately configurable rather than fixed: a single owner-operator running
 * one till and a chain with forty staff should not be forced onto the same
 * policy, and a rule nobody can live with just produces passwords on sticky
 * notes.
 */
final class PasswordPolicy
{
    /** @param array<string,mixed> $settings `restaurant_settings` row */
    public function __construct(private readonly array $settings)
    {
    }

    public function minLength(): int
    {
        return max(4, (int) ($this->settings['password_min_length'] ?? 6));
    }

    public function requiresUpper(): bool
    {
        return (int) ($this->settings['password_require_upper'] ?? 0) === 1;
    }

    public function requiresNumber(): bool
    {
        return (int) ($this->settings['password_require_number'] ?? 0) === 1;
    }

    public function requiresSymbol(): bool
    {
        return (int) ($this->settings['password_require_symbol'] ?? 0) === 1;
    }

    /** @return list<string> Human-readable rules, for the client to display. */
    public function describe(): array
    {
        $rules = [sprintf('At least %d characters', $this->minLength())];

        if ($this->requiresUpper()) {
            $rules[] = 'An uppercase letter';
        }
        if ($this->requiresNumber()) {
            $rules[] = 'A number';
        }
        if ($this->requiresSymbol()) {
            $rules[] = 'A symbol';
        }

        return $rules;
    }

    /** @return array<string,mixed> */
    public function toArray(): array
    {
        return [
            'min_length'      => $this->minLength(),
            'require_upper'   => $this->requiresUpper(),
            'require_number'  => $this->requiresNumber(),
            'require_symbol'  => $this->requiresSymbol(),
            'rules'           => $this->describe(),
        ];
    }

    /**
     * Throws a field-level validation error listing every unmet rule at once —
     * one failure at a time turns setting a password into a guessing game.
     */
    public function assert(string $password, string $field = 'password'): void
    {
        $failures = [];

        if (mb_strlen($password) < $this->minLength()) {
            $failures[] = sprintf('at least %d characters', $this->minLength());
        }
        if ($this->requiresUpper() && preg_match('/[A-Z]/', $password) !== 1) {
            $failures[] = 'an uppercase letter';
        }
        if ($this->requiresNumber() && preg_match('/[0-9]/', $password) !== 1) {
            $failures[] = 'a number';
        }
        if ($this->requiresSymbol() && preg_match('/[^A-Za-z0-9]/', $password) !== 1) {
            $failures[] = 'a symbol';
        }

        if ($failures !== []) {
            throw ApiException::validation([
                $field => 'Password needs ' . implode(', ', $failures),
            ]);
        }
    }

    public function hash(string $password): string
    {
        return password_hash(
            $password,
            PASSWORD_BCRYPT,
            ['cost' => (int) Config::get('auth.bcrypt_cost', 10)],
        );
    }
}
