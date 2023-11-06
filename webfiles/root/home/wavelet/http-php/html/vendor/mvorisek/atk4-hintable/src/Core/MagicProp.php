<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Core;

/**
 * @template TTargetClass of object
 * @template TReturnType
 *
 * @extends MagicAbstract<TTargetClass, TReturnType>
 */
class MagicProp extends MagicAbstract
{
    public const TYPE_PROPERTY_NAME = 'p_n';
    public const TYPE_PROPERTY_NAME_FULL = 'p_nf';

    public function __get(string $name): string
    {
        if ($this->_atk__core__hintable_magic__type === self::TYPE_PROPERTY_NAME) {
            return $name;
        }

        if ($this->_atk__core__hintable_magic__type === self::TYPE_PROPERTY_NAME_FULL) {
            return $this->_atk__core__hintable_magic__buildFullName($name);
        }

        throw $this->_atk__core__hintable_magic__createNotSupportedException();
    }
}
