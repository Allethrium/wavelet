<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Core;

use Mvorisek\Atk4\Hintable\Core\PropTrait;
use Mvorisek\Atk4\Hintable\Phpstan\PhpstanUtil;

class PropMock
{
    use PropTrait;

    /** @var string */
    public $pub = '_pub_';
    /** @var string */
    private $priv = '_priv_';
    /** @var int */
    public $pubInt = 21;

    protected function ignoreUnusedPrivate(): void
    {
        PhpstanUtil::ignoreUnusedVariable($this->priv);
    }
}
