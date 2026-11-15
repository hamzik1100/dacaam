<?php

declare(strict_types=1);

namespace DacaamAdmin\Core;

use RuntimeException;

/**
 * A message for the person using the page, not a fault in the code.
 *
 * "Enter a valid email address" and "Call to undefined function exec()" were
 * both RuntimeExceptions, so the router wrote both to the error log, so the
 * Health page listed both. That makes the log useless in the way that matters:
 * a real fault, arriving once, sits below a hundred typos and nobody looks.
 *
 * Throwing this says the request was refused on purpose. The user still sees
 * the message; the log does not.
 */
final class Refused extends RuntimeException
{
}
