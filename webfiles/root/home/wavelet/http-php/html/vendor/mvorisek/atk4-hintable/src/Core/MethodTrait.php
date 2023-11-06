<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Core;

trait MethodTrait
{
    /**
     * Returns a magic class that pretends to be instance of this class, but in reality
     * any method call returns its (short) name.
     *
     * @return static
     *
     * @phpstan-return MagicMethod<static, string>
     */
    public function methodName()
    {
        return Method::methodName($this);
    }

    /**
     * Returns a magic class that pretends to be instance of this class, but in reality
     * any method call returns its full name, ie. class name + "::" + short name.
     *
     * @return static
     *
     * @phpstan-return MagicMethod<static, string>
     */
    public function methodNameFull()
    {
        return Method::methodNameFull($this);
    }

    /**
     * Returns a magic class that pretends to be instance of this class, but in reality
     * any method call returns its Closure bound to static.
     *
     * @return static
     *
     * @phpstan-return MagicMethod<static, \Closure>
     */
    public function methodClosure()
    {
        return Method::methodClosure($this);
    }

    /**
     * Returns a magic class that pretends to be instance of this class, but in reality
     * any method call returns its Closure bound to the target class.
     *
     * @return static
     *
     * @phpstan-return MagicMethod<static, \Closure>
     */
    public function methodClosureProtected()
    {
        return Method::methodClosureProtected($this);
    }
}
