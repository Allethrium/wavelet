<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Core;

use Mvorisek\Atk4\Hintable\Core\MethodTrait;

class MethodMock
{
    use MethodTrait;

    private function priv(): string
    {
        return __METHOD__;
    }

    public function pub(): string
    {
        return __METHOD__;
    }

    private static function privStat(): string
    {
        return __METHOD__;
    }

    public static function pubStat(): string
    {
        return __METHOD__;
    }

    protected function ignoreUnusedPrivate(): void
    {
        $this->priv();
        self::privStat();
    }
}
