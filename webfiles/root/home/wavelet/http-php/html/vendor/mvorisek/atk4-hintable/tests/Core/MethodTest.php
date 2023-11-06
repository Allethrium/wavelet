<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Core;

use Atk4\Core\Exception;
use Atk4\Core\Phpunit\TestCase;
use Mvorisek\Atk4\Hintable\Core\Method;

/**
 * @coversDefaultClass \Mvorisek\Atk4\Hintable\Core\MagicMethod
 */
class MethodTest extends TestCase
{
    public function testMethodName(): void
    {
        $mock = new MethodMock();
        self::assertSame('pub', $mock->methodName()->pub());
        self::assertSame('priv', $mock->methodName()->priv());
        self::assertSame('undeclared', $mock->methodName()->undeclared()); // @phpstan-ignore-line
    }

    public function testMethodNameFull(): void
    {
        $mock = new MethodMock();
        self::assertSame(MethodMock::class . '::pub', $mock->methodNameFull()->pub());
        self::assertSame(MethodMock::class . '::priv', $mock->methodNameFull()->priv());
        self::assertSame(MethodMock::class . '::undeclared', $mock->methodNameFull()->undeclared()); // @phpstan-ignore-line
        self::assertSame(\stdClass::class . '::undeclared', Method::methodNameFull(\stdClass::class)->undeclared()); // @phpstan-ignore-line
    }

    public function testPropertyAccessException(): void
    {
        $mock = new MethodMock();
        $this->expectException(Exception::class);
        $mock->methodName()->undeclared; // @phpstan-ignore-line
    }

    public function testMethodClosure(): void
    {
        $mock = new MethodMock();
        self::assertSame(MethodMock::class . '::pub', $mock->methodClosure()->pub()());
    }

    public function testMethodClosureStatic(): void
    {
        $mock = new MethodMock();

        // calling static method as instance method is valid in PHP
        // and also the only supported option by us
        self::assertSame(MethodMock::class . '::pubStat', $mock->methodClosure()->pubStat()());

        $this->expectException(Exception::class);
        self::assertSame(MethodMock::class . '::pubStat', $mock->methodClosure()::pubStat()()); // @phpstan-ignore-line
    }

    public function testMethodClosureProtected(): void
    {
        $mock = new MethodMock();
        self::assertSame(MethodMock::class . '::priv', $mock->methodClosureProtected()->priv()());
        self::assertSame(MethodMock::class . '::privStat', $mock->methodClosureProtected()->privStat()());
    }

    public function testMethodClosureAnonymous(): void
    {
        $mock = new class() extends \stdClass {
            private function privAnon(): string
            {
                return __METHOD__;
            }

            private static function privAnonStat(): string
            {
                return __METHOD__;
            }

            protected function ignoreUnusedPrivate(): void
            {
                $this->privAnon();
                self::privAnonStat();
            }
        };

        self::assertSame(get_class($mock) . '::privAnon', Method::methodClosureProtected($mock)->privAnon()());
        self::assertSame(get_class($mock) . '::privAnonStat', Method::methodClosureProtected($mock)->privAnonStat()());
        self::assertSame(get_class($mock) . '::privAnonStat', Method::methodClosureProtected(get_class($mock))->privAnonStat()());
    }
}
