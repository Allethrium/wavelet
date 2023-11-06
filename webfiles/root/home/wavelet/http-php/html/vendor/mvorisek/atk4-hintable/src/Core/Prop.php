<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Core;

class Prop
{
    private function __construct()
    {
    }

    /**
     * Returns a magic class, document it using phpdoc as an instance of the target class,
     * any property returns its (short) name.
     *
     * @template T of object
     *
     * @param T|class-string<T> $targetClass
     *
     * @return object
     *
     * @phpstan-return MagicProp<T, string>
     */
    public static function propName($targetClass)
    {
        $cl = MagicProp::class;

        return new $cl($targetClass, MagicProp::TYPE_PROPERTY_NAME);
    }

    /**
     * Returns a magic class, document it using phpdoc as an instance of the target class,
     * any property returns its full name, ie. class name + "::" + short name.
     *
     * @template T of object
     *
     * @param T|class-string<T> $targetClass
     *
     * @return object
     *
     * @phpstan-return MagicProp<T, string>
     */
    public static function propNameFull($targetClass)
    {
        $cl = MagicProp::class;

        return new $cl($targetClass, MagicProp::TYPE_PROPERTY_NAME_FULL);
    }
}
