<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Phpstan;

class PhpstanUtil
{
    /**
     * @phpstan-impure
     */
    final public static function alwaysFalseAnalyseOnly(): bool
    {
        return false;
    }

    /**
     * @param mixed $value
     */
    final public static function ignoreUnusedVariable($value): void
    {
        if (self::alwaysFalseAnalyseOnly()) {
            assert($value !== null);
        }
    }

    /**
     * @return true
     *
     * @phpstan-impure
     */
    private static function fakeAlwaysTrue(): bool
    {
        return false; // @phpstan-ignore-line
    }

    /**
     * @return never
     */
    final public static function fakeNeverReturn(): void
    {
        if (self::fakeAlwaysTrue()) { // @phpstan-ignore-line
            throw new \Error();
        }
    }
}
