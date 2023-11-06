<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Core;

class Method
{
    private function __construct()
    {
    }

    /**
     * Returns a magic class, document it using phpdoc as an instance of the target class,
     * any method call returns its (short) name.
     *
     * @template T of object
     *
     * @param T|class-string<T> $targetClass
     *
     * @return object
     *
     * @phpstan-return MagicMethod<T, string>
     */
    public static function methodName($targetClass)
    {
        $cl = MagicMethod::class;

        return new $cl($targetClass, MagicMethod::TYPE_METHOD_NAME);
    }

    /**
     * Returns a magic class, document it using phpdoc as an instance of the target class,
     * any method call returns its full name, ie. class name + "::" + short name.
     *
     * @template T of object
     *
     * @param T|class-string<T> $targetClass
     *
     * @return object
     *
     * @phpstan-return MagicMethod<T, string>
     */
    public static function methodNameFull($targetClass)
    {
        $cl = MagicMethod::class;

        return new $cl($targetClass, MagicMethod::TYPE_METHOD_NAME_FULL);
    }

    /**
     * Returns a magic class, document it using phpdoc as an instance of the target class,
     * any method call returns its Closure bound to static.
     *
     * @template T of object
     *
     * @param T|class-string<T> $targetClass string is supported only for static methods
     *
     * @return object
     *
     * @phpstan-return MagicMethod<T, \Closure>
     */
    public static function methodClosure($targetClass)
    {
        $cl = MagicMethod::class;

        return new $cl($targetClass, MagicMethod::TYPE_METHOD_CLOSURE);
    }

    /**
     * Returns a magic class, document it using phpdoc as an instance of the target class,
     * any method call returns its Closure bound to the target class.
     *
     * @template T of object
     *
     * @param T|class-string<T> $targetClass string is supported only for static methods
     *
     * @return object
     *
     * @phpstan-return MagicMethod<T, \Closure>
     */
    public static function methodClosureProtected($targetClass)
    {
        $cl = MagicMethod::class;

        return new $cl($targetClass, MagicMethod::TYPE_METHOD_CLOSURE_PROTECTED);
    }
}
