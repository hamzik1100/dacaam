<?php

declare(strict_types=1);

namespace Dacaam\Core;

/**
 * Request validation.
 *
 * Backend validation is mandatory even where Flutter already checks the same
 * thing: the client validates for UX, the server validates for truth. A
 * request that bypasses the app entirely must still be rejected here.
 *
 * Rules: `required`, `string`, `int`, `numeric`, `bool`, `array`,
 * `min:n`, `max:n`, `in:a,b,c`, `date`, `phone`, `nullable`.
 */
final class Validator
{
    /** @var array<string,string> */
    private array $errors = [];

    /** @var array<string,mixed> */
    private array $validated = [];

    /**
     * @param array<string,mixed>  $data
     * @param array<string,string> $rules field => 'required|int|min:1'
     */
    public function __construct(
        private readonly array $data,
        private readonly array $rules,
    ) {
        $this->run();
    }

    /**
     * @param  array<string,mixed>  $data
     * @param  array<string,string> $rules
     * @return array<string,mixed>
     */
    public static function check(array $data, array $rules): array
    {
        $validator = new self($data, $rules);
        if ($validator->fails()) {
            throw ApiException::validation($validator->errors());
        }

        return $validator->validated();
    }

    public function fails(): bool
    {
        return $this->errors !== [];
    }

    /** @return array<string,string> */
    public function errors(): array
    {
        return $this->errors;
    }

    /** @return array<string,mixed> */
    public function validated(): array
    {
        return $this->validated;
    }

    private function run(): void
    {
        foreach ($this->rules as $field => $ruleString) {
            $rules = explode('|', $ruleString);
            $present = array_key_exists($field, $this->data);
            $value = $this->data[$field] ?? null;

            $nullable = in_array('nullable', $rules, true);
            $required = in_array('required', $rules, true);

            if ($required && (!$present || $value === null || $value === '')) {
                $this->errors[$field] = 'This field is required';
                continue;
            }

            if (!$present || ($value === null && $nullable)) {
                if ($present) {
                    $this->validated[$field] = null;
                }
                continue;
            }

            $cast = $value;
            foreach ($rules as $rule) {
                if ($rule === 'required' || $rule === 'nullable') {
                    continue;
                }

                [$name, $arg] = array_pad(explode(':', $rule, 2), 2, null);

                switch ($name) {
                    case 'string':
                        if (!is_scalar($cast)) {
                            $this->errors[$field] = 'Must be text';
                            continue 3;
                        }
                        $cast = trim((string) $cast);
                        break;

                    case 'int':
                        if (!is_numeric($cast)) {
                            $this->errors[$field] = 'Must be a whole number';
                            continue 3;
                        }
                        $cast = (int) $cast;
                        break;

                    case 'numeric':
                        if (!is_numeric($cast)) {
                            $this->errors[$field] = 'Must be a number';
                            continue 3;
                        }
                        $cast = (float) $cast;
                        break;

                    case 'bool':
                        $cast = filter_var($cast, FILTER_VALIDATE_BOOL, FILTER_NULL_ON_FAILURE) ?? false;
                        break;

                    case 'array':
                        if (!is_array($cast)) {
                            $this->errors[$field] = 'Must be a list';
                            continue 3;
                        }
                        break;

                    // min/max dispatch on the PHP type produced by the rules
                    // that ran before them, not on `is_numeric`. A phone like
                    // "0634567890" is a numeric *string*, and comparing it as
                    // a number against `max:32` would reject every phone in
                    // the country.
                    case 'min':
                        $min = (float) $arg;
                        if ((is_int($cast) || is_float($cast)) && (float) $cast < $min) {
                            $this->errors[$field] = sprintf('Must be at least %s', $arg);
                            continue 3;
                        }
                        if (is_string($cast) && mb_strlen($cast) < $min) {
                            $this->errors[$field] = sprintf('Must be at least %s characters', $arg);
                            continue 3;
                        }
                        if (is_array($cast) && count($cast) < $min) {
                            $this->errors[$field] = sprintf('Needs at least %s entries', $arg);
                            continue 3;
                        }
                        break;

                    case 'max':
                        $max = (float) $arg;
                        if ((is_int($cast) || is_float($cast)) && (float) $cast > $max) {
                            $this->errors[$field] = sprintf('Must be at most %s', $arg);
                            continue 3;
                        }
                        if (is_string($cast) && mb_strlen($cast) > $max) {
                            $this->errors[$field] = sprintf('Must be at most %s characters', $arg);
                            continue 3;
                        }
                        if (is_array($cast) && count($cast) > $max) {
                            $this->errors[$field] = sprintf('At most %s entries', $arg);
                            continue 3;
                        }
                        break;

                    case 'in':
                        $allowed = explode(',', (string) $arg);
                        if (!in_array((string) $cast, $allowed, true)) {
                            $this->errors[$field] = sprintf('Must be one of: %s', (string) $arg);
                            continue 3;
                        }
                        break;

                    case 'date':
                        if (strtotime((string) $cast) === false) {
                            $this->errors[$field] = 'Must be a valid date';
                            continue 3;
                        }
                        break;

                    case 'phone':
                        $digits = preg_replace('/[^0-9+]/', '', (string) $cast) ?? '';
                        if (mb_strlen($digits) < 7) {
                            $this->errors[$field] = 'Must be a valid phone number';
                            continue 3;
                        }
                        $cast = $digits;
                        break;
                }
            }

            $this->validated[$field] = $cast;
        }
    }
}
