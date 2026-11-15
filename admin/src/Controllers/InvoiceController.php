<?php

declare(strict_types=1);

namespace DacaamAdmin\Controllers;

use Dacaam\Core\Database;
use Dacaam\Core\Mailer;
use DacaamAdmin\Core\Flash;
use DacaamAdmin\Core\PlatformAudit;
use DacaamAdmin\Core\Refused;
use DacaamAdmin\Core\Response;
use DacaamAdmin\Core\View;

/**
 * A receipt for each subscription payment.
 *
 * Restaurants paying by ZAAD or bank transfer asked for something to put in
 * their books, and got a screenshot of this dashboard. Every recorded payment
 * now has a numbered invoice: a page that prints cleanly (or saves as PDF from
 * the browser's print dialog), and the same text by email.
 *
 * The number is derived from the payment id, so it can never be reused or
 * skipped, and nothing extra has to be kept in step.
 */
final class InvoiceController
{
    /** Where the issuer's details live, and what they default to. */
    public const SETTINGS = [
        'invoice_business_name'    => 'DACAAM',
        'invoice_business_address' => '',
        'invoice_business_phone'   => '',
        'invoice_business_email'   => '',
        'invoice_footer'           => 'Thank you for using DACAAM.',
    ];

    /** @param array<string,string> $params */
    public function show(array $params): void
    {
        $invoice = self::load((int) $params['id']);

        View::render('invoice', $invoice + ['issuer' => self::issuer()]);
    }

    /** @param array<string,string> $params */
    public function email(array $params): void
    {
        $invoice = self::load((int) $params['id']);
        $payment = $invoice['payment'];
        $restaurant = $invoice['restaurant'];

        $emails = array_column(
            Database::select(
                'SELECT DISTINCT u.email
                   FROM users u
                   JOIN user_roles ur ON ur.user_id = u.id
                   JOIN roles ro ON ro.id = ur.role_id
                  WHERE u.restaurant_id = :rid AND u.is_active = 1 AND ro.code = "admin"
                    AND u.email IS NOT NULL AND u.email <> ""',
                ['rid' => $restaurant['id']],
            ),
            'email',
        );
        $emails = array_values(array_filter(
            $emails,
            static fn ($e): bool => filter_var((string) $e, FILTER_VALIDATE_EMAIL) !== false,
        ));

        if ($emails === []) {
            throw new Refused(
                'None of this restaurant\'s admins has an email address. Add one in the app first.',
            );
        }

        foreach ($emails as $email) {
            Database::insert('email_outbox', [
                'restaurant_id' => (int) $restaurant['id'],
                'to_email'      => (string) $email,
                'subject'       => sprintf('Invoice %s — %s', $invoice['number'], self::issuer()['invoice_business_name']),
                'body'          => self::text($invoice),
                'event_key'     => 'subscription.invoice',
                'record_id'     => (int) $payment['id'],
            ]);
        }

        PlatformAudit::log(
            'invoice_emailed',
            restaurantId: (int) $restaurant['id'],
            detail: $invoice['number'] . ' → ' . implode(', ', $emails),
        );

        Flash::success(sprintf(
            'Invoice %s queued for %s.%s',
            $invoice['number'],
            implode(', ', $emails),
            Mailer::isConfigured() ? '' : ' Mail is not set up yet — it goes out once SMTP is configured in Settings.',
        ));
        Response::redirect('/restaurants/' . $restaurant['id']);
    }

    public static function number(array $payment): string
    {
        return sprintf('INV-%s-%05d', date('Y', (int) strtotime((string) $payment['paid_on'])), (int) $payment['id']);
    }

    /** @return array<string,string> */
    public static function issuer(): array
    {
        $rows = Database::select(
            'SELECT key_name, value FROM system_settings WHERE key_name LIKE "invoice\_%"',
        );
        $stored = array_column($rows, 'value', 'key_name');

        $out = [];
        foreach (self::SETTINGS as $key => $default) {
            $value = trim((string) ($stored[$key] ?? ''));
            $out[$key] = $value !== '' ? $value : $default;
        }

        return $out;
    }

    /** @return array{payment:array,restaurant:array,subscription:?array,number:string} */
    private static function load(int $id): array
    {
        $payment = Database::selectOne(
            'SELECT * FROM subscription_payments WHERE id = :id LIMIT 1',
            ['id' => $id],
        );

        if ($payment === null) {
            Response::notFound();
        }

        $restaurant = Database::selectOne(
            'SELECT * FROM restaurants WHERE id = :id LIMIT 1',
            ['id' => $payment['restaurant_id']],
        ) ?? Response::notFound();

        return [
            'payment'      => $payment,
            'restaurant'   => $restaurant,
            'subscription' => Database::selectOne(
                'SELECT * FROM subscriptions WHERE id = :id LIMIT 1',
                ['id' => $payment['subscription_id']],
            ),
            'number'       => self::number($payment),
        ];
    }

    /** The same invoice as plain text, for email. */
    private static function text(array $invoice): string
    {
        $issuer = self::issuer();
        $p = $invoice['payment'];
        $r = $invoice['restaurant'];
        $plan = (string) ($p['plan'] ?? '') !== ''
            ? (string) $p['plan']
            : (string) ($invoice['subscription']['plan'] ?? '');

        $lines = [
            $issuer['invoice_business_name'],
            ...array_filter([
                $issuer['invoice_business_address'],
                $issuer['invoice_business_phone'],
                $issuer['invoice_business_email'],
            ]),
            '',
            'INVOICE ' . $invoice['number'] . ' — PAID',
            'Date: ' . date('j M Y', (int) strtotime((string) $p['paid_on'])),
            '',
            'Billed to: ' . $r['name'] . ' (' . $r['slug'] . ')',
            '',
            'Subscription' . ($plan !== '' ? ' — ' . ucfirst($plan) . ' plan' : ''),
        ];

        if ($p['months'] !== null) {
            $lines[] = sprintf('%d month(s)', (int) $p['months']);
        }
        if ($p['period_start'] !== null && $p['period_end'] !== null) {
            $lines[] = sprintf(
                'Period: %s to %s',
                date('j M Y', (int) strtotime((string) $p['period_start'])),
                date('j M Y', (int) strtotime((string) $p['period_end'])),
            );
        }

        $lines[] = '';
        $lines[] = 'Amount paid: SLSH ' . number_format((float) $p['amount'], 0);
        $lines[] = 'Method: ' . strtoupper((string) $p['method'])
            . ((string) $p['reference'] !== '' ? ' — ref ' . $p['reference'] : '');
        $lines[] = '';
        $lines[] = $issuer['invoice_footer'];

        return implode("\n", $lines);
    }
}
