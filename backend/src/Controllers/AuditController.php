<?php

declare(strict_types=1);

namespace Dacaam\Controllers;

use Dacaam\Core\AuthContext;
use Dacaam\Core\Database;
use Dacaam\Core\Request;
use Dacaam\Support\Period;
use Dacaam\Support\Presenter;

final class AuditController
{
    /** @return list<array<string,mixed>> */
    public function index(Request $request, AuthContext $context): array
    {
        $where = ['restaurant_id = :rid'];
        $bind = ['rid' => $context->restaurantId];

        if (($module = $request->queryString('module')) !== '') {
            $where[] = 'module = :module';
            $bind['module'] = $module;
        }
        if (($userId = $request->queryInt('user_id')) !== null) {
            $where[] = 'user_id = :uid';
            $bind['uid'] = $userId;
        }

        $range = $request->queryString('range');
        if ($range !== '' && $range !== 'all') {
            $period = Period::resolve($range, $request->queryString('from'), $request->queryString('to'));
            $where[] = 'created_at BETWEEN :from AND :to';
            $bind['from'] = $period->fromSql();
            $bind['to'] = $period->toSql();
        }

        return array_map(
            [Presenter::class, 'auditEvent'],
            Database::select(
                'SELECT * FROM audit_logs WHERE ' . implode(' AND ', $where)
                . ' ORDER BY created_at DESC, id DESC LIMIT 300',
                $bind,
            ),
        );
    }
}
