<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Phpstan;

use Atk4\Core\Phpunit\TestCase;
use Mvorisek\Atk4\Hintable\Phpstan\AssertSamePhpstanTypeTrait;
use Mvorisek\Atk4\Hintable\Tests\Phpstan\SeedDemo\Bodyshop;
use Mvorisek\Atk4\Hintable\Tests\Phpstan\SeedDemo\Car;
use Mvorisek\Atk4\Hintable\Tests\Phpstan\SeedDemo\CarDefault;
use Mvorisek\Atk4\Hintable\Tests\Phpstan\SeedDemo\CarExtra;
use Mvorisek\Atk4\Hintable\Tests\Phpstan\SeedDemo\CarGeneric;

class SeedDmrtExtensionTest extends TestCase
{
    use AssertSamePhpstanTypeTrait;

    public function testSeedArray(): void
    {
        $car = Car::fromSeed([Car::class]);
        self::assertSamePhpstanType(Car::class, $car);
        self::assertSame(Car::class, get_class($car));

        $seed = [CarExtra::class];
        $car = Car::fromSeed($seed);
        self::assertSamePhpstanType(CarExtra::class, $car);
        self::assertSame(CarExtra::class, get_class($car));

        $bodyshop = new Bodyshop();
        $car = $bodyshop->acceptCar('a', [Car::class]);
        self::assertSamePhpstanType(Car::class, $car);
        self::assertSame(Car::class, get_class($car));

        $car = $bodyshop->acceptCar('b', [CarExtra::class]);
        self::assertSamePhpstanType(CarExtra::class, $car);
        self::assertSame(CarExtra::class, get_class($car));
    }

    public function testSeedArrayithGeneric(): void
    {
        /** @var array{0:class-string<CarGeneric<\DateTime>>} */
        $seed = [CarGeneric::class]; // @phpstan-ignore-line https://github.com/phpstan/phpstan/issues/9189
        $car = Car::fromSeed($seed);
        self::assertSamePhpstanType(CarGeneric::class . '<DateTime>', $car);
        self::assertSame(CarGeneric::class, get_class($car));
    }

    public function testSeedObject(): void
    {
        $car = Car::fromSeed(new Car());
        self::assertSamePhpstanType(Car::class, $car);
        self::assertSamePhpstanType(Car::class, $car);
        self::assertSame(Car::class, get_class($car));

        $seed = new CarExtra();
        $car = Car::fromSeed($seed);
        self::assertSamePhpstanType(CarExtra::class, $car);
        self::assertSame($seed, $car);

        /** @var CarGeneric<\DateTime> */
        $seed = new CarGeneric();
        $car = Car::fromSeed($seed);
        self::assertSamePhpstanType(CarGeneric::class . '<DateTime>', $car);
        self::assertSame(CarGeneric::class, get_class($car));
    }

    public function testSeedUndefined(): void
    {
        $car = Car::fromSeed();
        self::assertSamePhpstanType(Car::class, $car);
        self::assertSame(CarDefault::class, get_class($car));

        $bodyshop = new Bodyshop();
        $car = $bodyshop->acceptCar('a');
        self::assertSamePhpstanType(Car::class, $car);
        self::assertSame(CarDefault::class, get_class($car));
    }

    public function testSeedEmpty(): void
    {
        $car = Car::fromSeed(null);
        self::assertSamePhpstanType(Car::class, $car);
        self::assertSame(CarDefault::class, get_class($car));

        $car = Car::fromSeed([]);
        self::assertSamePhpstanType(Car::class, $car);
        self::assertSame(CarDefault::class, get_class($car));
    }

    public function testIntersectNever(): void
    {
        $this->expectException(\TypeError::class);
        $car = Car::fromSeed(new \stdClass());
        self::assertSamePhpstanType('*NEVER*', $car);
    }
}
