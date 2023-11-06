<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Core;

/**
 * @template TTargetClass of object
 * @template TReturnType
 *
 * @extends MagicAbstract<TTargetClass, TReturnType>
 */
class MagicMethod extends MagicAbstract
{
    public const TYPE_METHOD_NAME = 'm_n';
    public const TYPE_METHOD_NAME_FULL = 'm_nf';
    /** Closure will be bound to static */
    public const TYPE_METHOD_CLOSURE = 'm_c';
    /** Closure will be bound to the target class */
    public const TYPE_METHOD_CLOSURE_PROTECTED = 'm_cp';

    /**
     * @return string|\Closure
     */
    public function __call(string $name, array $args)
    {
        if ($this->_atk__core__hintable_magic__type === self::TYPE_METHOD_NAME) {
            return $name;
        }

        if ($this->_atk__core__hintable_magic__type === self::TYPE_METHOD_NAME_FULL) {
            return $this->_atk__core__hintable_magic__buildFullName($name);
        }

        $cl = $this->_atk__core__hintable_magic__class;

        if ($this->_atk__core__hintable_magic__type === self::TYPE_METHOD_CLOSURE) {
            return (static function () use ($cl, $name) {
                return \Closure::fromCallable([$cl, $name]);
            })();
        }

        if ($this->_atk__core__hintable_magic__type === self::TYPE_METHOD_CLOSURE_PROTECTED) {
            return \Closure::bind(static function () use ($cl, $name) {
                return \Closure::fromCallable([$cl, $name]);
            }, null, $cl)();
        }

        throw $this->_atk__core__hintable_magic__createNotSupportedException();
    }
}
