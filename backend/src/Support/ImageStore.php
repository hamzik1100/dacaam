<?php

declare(strict_types=1);

namespace Dacaam\Support;

use Dacaam\Core\ApiException;
use Dacaam\Core\Config;

/**
 * Writes menu photographs to disk and hands back the address they serve from.
 *
 * The phone does the resizing before it sends anything — 800px, JPEG quality
 * 85, which turns a 4 MB camera frame into about 100 KB. That order matters
 * more than it looks:
 *
 *   - The upload is what the staff member waits for, on a connection they pay
 *     for by the megabyte. Sending the full frame so the server can shrink it
 *     spends their money and their time to save ours.
 *   - Shared hosting does not reliably have an image library, and finding that
 *     out in production is a bad afternoon. Nothing here needs one: the file
 *     is validated, not re-encoded.
 *
 * So this class is deliberately small. It proves the bytes really are an
 * image, gives the file a name nobody chose, and puts it somewhere the web
 * server will serve but never execute.
 */
final class ImageStore
{
    /** Anything larger is a phone that ignored the resize, or something else. */
    private const MAX_BYTES = 2 * 1024 * 1024;

    private const ALLOWED = [
        IMAGETYPE_JPEG => 'jpg',
        IMAGETYPE_PNG  => 'png',
        IMAGETYPE_WEBP => 'webp',
    ];

    private function __construct()
    {
    }

    /**
     * Stores a base64 image and returns its public URL.
     *
     * Base64 is the transport, not the storage: it rides in the JSON body the
     * rest of the API already speaks, costs a third more bytes for one request,
     * and is decoded to real bytes on the way to disk. Keeping the encoded form
     * in the database would put every picture inside every menu response.
     */
    public static function putMenuImage(string $base64, int $restaurantId): string
    {
        $raw = base64_decode(self::stripDataUrl($base64), true);

        if ($raw === false || $raw === '') {
            throw ApiException::validation(['image' => 'That is not a readable image']);
        }

        if (strlen($raw) > self::MAX_BYTES) {
            throw ApiException::validation([
                'image' => sprintf('Images must be under %d MB', self::MAX_BYTES / 1024 / 1024),
            ]);
        }

        // The bytes decide what this is, not the caller and not a file
        // extension. An upload named .jpg containing PHP is the oldest way to
        // own a server, and the only defence that actually works is refusing
        // anything the image parser does not recognise.
        $info = @getimagesizefromstring($raw);

        if ($info === false || !isset(self::ALLOWED[$info[2]])) {
            throw ApiException::validation(['image' => 'Only JPEG, PNG or WebP images are accepted']);
        }

        $extension = self::ALLOWED[$info[2]];
        $directory = self::directory();

        // Named from the content, so re-uploading the same photograph reuses
        // the file instead of littering the disk with copies.
        $name = sprintf('%d-%s.%s', $restaurantId, substr(sha1($raw), 0, 20), $extension);
        $path = $directory . DIRECTORY_SEPARATOR . $name;

        if (!file_exists($path) && file_put_contents($path, $raw) === false) {
            throw ApiException::unprocessable('Could not save the image');
        }

        @chmod($path, 0644);

        return self::baseUrl() . '/uploads/menu/' . $name;
    }

    /**
     * Removes a stored image. Silent when it is not ours or already gone —
     * a menu edit must not fail because a file somebody deleted by hand is
     * missing.
     */
    public static function forget(?string $url): void
    {
        if ($url === null || $url === '') {
            return;
        }

        $name = basename(parse_url($url, PHP_URL_PATH) ?: '');
        if ($name === '' || !str_contains($url, '/uploads/menu/')) {
            return;
        }

        $path = self::directory() . DIRECTORY_SEPARATOR . $name;
        if (is_file($path)) {
            @unlink($path);
        }
    }

    private static function directory(): string
    {
        $configured = Config::get('uploads.path');

        $base = is_string($configured) && $configured !== ''
            ? $configured
            // The directory the front controller was served from. In production
            // that is public_html/api, which is exactly what api.dhuuh.shop
            // serves; locally it is backend/public.
            : dirname((string) ($_SERVER['SCRIPT_FILENAME'] ?? '')) . '/uploads/menu';

        if (!is_dir($base) && !mkdir($base, 0755, true) && !is_dir($base)) {
            throw ApiException::unprocessable('The upload directory does not exist and could not be created');
        }

        self::protect(dirname($base));

        return $base;
    }

    /**
     * Drops an .htaccess beside the uploads that turns off PHP execution.
     *
     * Belt and braces. The validation above should already make it impossible
     * to store anything executable, but a directory the internet can write to
     * and the server will run is the one mistake worth defending twice.
     */
    private static function protect(string $uploadsRoot): void
    {
        $file = $uploadsRoot . DIRECTORY_SEPARATOR . '.htaccess';
        if (is_file($file)) {
            return;
        }

        @file_put_contents($file, <<<'HTACCESS'
        # Uploaded files are data. Nothing in here is ever executed.
        <IfModule mod_php.c>
            php_flag engine off
        </IfModule>
        RemoveHandler .php .phtml .php3 .php4 .php5 .php7 .php8
        RemoveType .php .phtml .php3 .php4 .php5 .php7 .php8
        HTACCESS);
    }

    private static function baseUrl(): string
    {
        $configured = Config::get('uploads.url');
        if (is_string($configured) && $configured !== '') {
            return rtrim($configured, '/');
        }

        $scheme = (($_SERVER['HTTPS'] ?? '') !== '' && $_SERVER['HTTPS'] !== 'off')
            ? 'https'
            : 'http';

        return $scheme . '://' . (string) ($_SERVER['HTTP_HOST'] ?? 'localhost');
    }

    private static function stripDataUrl(string $value): string
    {
        // Browsers and some pickers hand over `data:image/jpeg;base64,...`.
        $comma = strpos($value, ',');

        return str_starts_with($value, 'data:') && $comma !== false
            ? substr($value, $comma + 1)
            : $value;
    }
}
