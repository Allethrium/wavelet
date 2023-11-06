<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Phpstan\SeedDemo;

class Bodyshop
{
    /**
     * @param array<mixed>|object|null $seed
     *
     * @return Car
     */
    public function acceptCar(string $name, $seed = [])
    {
        return Car::fromSeed($seed);
    }
}
