<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Phpstan;

use Atk4\Core\Phpunit\TestCase;
use Mvorisek\Atk4\Hintable\Phpstan\PhpstanUtil;

class PhpstanUtilTest extends TestCase
{
    /**
     * @doesNotPerformAssertions
     */
    public function testAlwaysFalseAnalyseOnly(): void
    {
        if (PhpstanUtil::alwaysFalseAnalyseOnly()) {
            self::assertTrue(false); // @phpstan-ignore-line
        }
    }

    public function testUseVariable(): void
    {
        (static function (string $name): void { // ignore this line once phpstan emits an error for unused variable
            self::assertTrue(true); // @phpstan-ignore-line
        })('');

        (static function (string $name): void {
            PhpstanUtil::ignoreUnusedVariable($name);

            self::assertTrue(true); // @phpstan-ignore-line
        })('');
    }

    public function testFakeNeverReturn(): void
    {
        /**
         * @return never
         */
        $fx = static function () {
            PhpstanUtil::fakeNeverReturn();
        };

        $fxRes = PhpstanUtil::alwaysFalseAnalyseOnly() ? false : $fx();
        if (PhpstanUtil::alwaysFalseAnalyseOnly()) {
            self::assertFalse($fxRes); // @phpstan-ignore-line
        }
        self::assertNull($fxRes); // @phpstan-ignore-line
    }
}
