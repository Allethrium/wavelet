<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Phpstan;

use Atk4\Core\Phpunit\TestCase;
use Mvorisek\Atk4\Hintable\Phpstan\AssertSamePhpstanTypeTrait;

class AssertSamePhpstanTypeTest extends TestCase
{
    use AssertSamePhpstanTypeTrait;

    /**
     * @return \DateTimeInterface
     */
    private function demoReturnTypeSimple()
    {
        return new \DateTime();
    }

    /**
     * @return \DateTimeInterface|\stdClass
     */
    private function demoReturnTypeUnion()
    {
        return new \stdClass();
    }

    /**
     * @return \stdClass&\Traversable<\DateTime>
     */
    private function demoReturnTypeIntersect()
    {
        return new \stdClass();
    }

    /**
     * @return class-string<\DateTimeInterface>
     */
    private function demoReturnTypeClassString()
    {
        return get_class(new \DateTime());
    }

    /**
     * @return array{1:positive-int}
     */
    private function demoReturnTypeArrayWithShape()
    {
        return [1 => 0, 'a' => 1]; // @phpstan-ignore-line
    }

    public function testFromExpression(): void
    {
        self::assertSamePhpstanType('null', null);
        $v = 0;
        self::assertSamePhpstanType('0', $v);
        self::assertSamePhpstanType('int<0, 10>', random_int(0, 10));
        self::assertSamePhpstanType(\DateTime::class, new \DateTime());
        self::assertSamePhpstanType('class-string<' . \DateTime::class . '>', get_class(new \DateTime()));
        self::assertSamePhpstanType('resource|false', fopen('php://memory', 'r'));
    }

    public function testFromPhpdoc(): void
    {
        self::assertSamePhpstanType('DateTimeInterface', $this->demoReturnTypeSimple());
        self::assertSamePhpstanType('DateTimeInterface|stdClass', $this->demoReturnTypeUnion());
        self::assertSamePhpstanType('stdClass&Traversable<mixed, DateTime>', $this->demoReturnTypeIntersect());
        self::assertSamePhpstanType('class-string<DateTimeInterface>', $this->demoReturnTypeClassString());
        self::assertSamePhpstanType('array{1: int<1, max>}', $this->demoReturnTypeArrayWithShape());
    }
}
