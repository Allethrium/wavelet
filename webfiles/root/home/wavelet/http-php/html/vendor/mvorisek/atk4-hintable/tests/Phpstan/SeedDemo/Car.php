<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Phpstan\SeedDemo;

use Atk4\Core\Factory;

class Car
{
    /**
     * @param array<mixed>|object|null $seed
     */
    public static function fromSeed($seed = []): self
    {
        $seed = Factory::mergeSeeds($seed ?? [], [CarDefault::class]);

        return Factory::factory($seed);
    }
}
