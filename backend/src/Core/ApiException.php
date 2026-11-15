<?php

declare(strict_types=1);

namespace Dacaam\Core;

use RuntimeException;
use Throwable;

/**
 * Any failure the client is allowed to see.
 *
 * Anything else bubbles up as a 500 with the detail withheld unless debug is
 * on — an internal error must never leak schema or file paths to a POS device.
 */
class ApiException extends RuntimeException
{
    /** @param array<string,string> $fields */
    public function __construct(
        string $message,
        private readonly int $status = 400,
        private readonly string $errorCode = 'bad_request',
        private readonly array $fields = [],
        ?Throwable $previous = null,
    ) {
        parent::__construct($message, $status, $previous);
    }

    public function status(): int
    {
        return $this->status;
    }

    public function errorCode(): string
    {
        return $this->errorCode;
    }

    /** @return array<string,string> */
    public function fields(): array
    {
        return $this->fields;
    }

    /** @param array<string,string> $fields */
    public static function validation(array $fields, string $message = 'Validation failed'): self
    {
        return new self($message, 422, 'validation_failed', $fields);
    }

    public static function unauthorized(string $message = 'Authentication required'): self
    {
        return new self($message, 401, 'unauthorized');
    }

    public static function forbidden(string $message = 'You do not have permission'): self
    {
        return new self($message, 403, 'forbidden');
    }

    public static function notFound(string $message = 'Not found'): self
    {
        return new self($message, 404, 'not_found');
    }

    public static function conflict(string $message): self
    {
        return new self($message, 409, 'conflict');
    }

    public static function unprocessable(string $message): self
    {
        return new self($message, 422, 'unprocessable');
    }
}
