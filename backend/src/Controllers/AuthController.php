<?php

declare(strict_types=1);

namespace Dacaam\Controllers;

use Dacaam\Core\Auth;
use Dacaam\Core\AuthContext;
use Dacaam\Core\Request;
use Dacaam\Core\Validator;

final class AuthController
{
    /** @return array<string,mixed> */
    public function login(Request $request): array
    {
        $data = Validator::check($request->all(), [
            'restaurant_code' => 'required|string|min:2|max:32',
            'phone'           => 'required|phone|max:32',
            'password'        => 'required|string|min:4|max:100',
        ]);

        return Auth::login(
            (string) $data['restaurant_code'],
            (string) $data['phone'],
            (string) $data['password'],
            $request,
        );
    }

    /**
     * Second step of a 2FA sign-in: exchange the challenge plus a code for a
     * session. Accepts a TOTP code or a recovery code.
     *
     * @return array<string,mixed>
     */
    public function verifyTwoFactor(Request $request): array
    {
        $data = Validator::check($request->all(), [
            'challenge' => 'required|string|min:16|max:128',
            'code'      => 'required|string|min:6|max:12',
        ]);

        return Auth::verifyTwoFactor(
            (string) $data['challenge'],
            (string) $data['code'],
            $request,
        );
    }

    /** @return array<string,mixed> */
    public function me(Request $request, AuthContext $context): array
    {
        return [
            'user'        => Auth::publicUser($context->userId),
            'permissions' => $context->permissions,
        ];
    }

    /** @return array<string,mixed> */
    public function logout(Request $request, AuthContext $context): array
    {
        Auth::logout($context);

        return ['logged_out' => true];
    }
}
