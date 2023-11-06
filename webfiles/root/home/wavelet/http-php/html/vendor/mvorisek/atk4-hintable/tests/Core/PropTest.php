<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Core;

use Atk4\Core\Exception;
use Atk4\Core\Phpunit\TestCase;
use Mvorisek\Atk4\Hintable\Core\Prop;

/**
 * @coversDefaultClass \Mvorisek\Atk4\Hintable\Core\MagicProp
 */
class PropTest extends TestCase
{
    public function testPropName(): void
    {
        $mock = new PropMock();
        self::assertSame('pub', $mock->propName()->pub);
        self::assertSame('priv', $mock->propName()->priv);
        self::assertSame('undeclared', $mock->propName()->undeclared); // @phpstan-ignore-line

        self::assertSame('_pub_', $mock->pub);
        self::assertSame('_pub_', $mock->{$mock->propName()->pub});
    }

    public function testPropNameFull(): void
    {
        $mock = new PropMock();
        self::assertSame(PropMock::class . '::pub', $mock->propNameFull()->pub);
        self::assertSame(PropMock::class . '::priv', $mock->propNameFull()->priv);
        self::assertSame(PropMock::class . '::undeclared', $mock->propNameFull()->undeclared); // @phpstan-ignore-line
        self::assertSame(\stdClass::class . '::undeclared', Prop::propNameFull(\stdClass::class)->undeclared);
    }

    public function testMethodAccessException(): void
    {
        $mock = new PropMock();
        $this->expectException(Exception::class);
        $mock->propName()->undeclared(); // @phpstan-ignore-line
    }

    public function testPhpstanPropNameStringType(): void
    {
        $mock = new PropMock();
        self::assertSame(21, $mock->pubInt);
        self::assertIsString($mock->propName()->pubInt); // @phpstan-ignore-line
        $this->expectException(\TypeError::class);
        self::assertSame('unused', chr($mock->propName()->pubInt)); // @phpstan-ignore-line
    }
}
