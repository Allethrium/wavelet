<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Core;

trait PropTrait
{
    /**
     * Returns a magic class that pretends to be instance of this class, but in reality
     * any property returns its (short) name.
     *
     * @return static
     *
     * @phpstan-return MagicProp<static, string>
     */
    public function propName()
    {
        return Prop::propName($this);
    }

    /**
     * Returns a magic class that pretends to be instance of this class, but in reality
     * any property returns its full name, ie. class name + "::" + short name.
     *
     * @return static
     *
     * @phpstan-return MagicProp<static, string>
     */
    public function propNameFull()
    {
        return Prop::propNameFull($this);
    }
}
