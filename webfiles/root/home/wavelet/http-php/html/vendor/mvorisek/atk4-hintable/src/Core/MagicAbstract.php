<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Core;

use Atk4\Core\Exception;

/**
 * @template TTargetClass of object
 * @template TReturnType
 *
 * @phpstan-consistent-constructor
 */
abstract class MagicAbstract
{
    /** @var TTargetClass|class-string<TTargetClass> */
    protected $_atk__core__hintable_magic__class;
    /** @var string */
    protected $_atk__core__hintable_magic__type;

    /**
     * @param TTargetClass|class-string<TTargetClass> $targetClass
     */
    public function __construct($targetClass, string $type)
    {
        if (is_string($targetClass)) { // normalize/validate string class name
            $targetClass = (new \ReflectionClass($targetClass))->getName();
        }

        $this->_atk__core__hintable_magic__class = $targetClass;
        $this->_atk__core__hintable_magic__type = $type;
    }

    protected function _atk__core__hintable_magic__createNotSupportedException(): Exception
    {
        $opName = debug_backtrace(\DEBUG_BACKTRACE_IGNORE_ARGS, 2)[1]['function'];

        return (new Exception('Operation "' . $opName . '" is not supported'))
            ->addMoreInfo('target_class', $this->_atk__core__hintable_magic__class)
            ->addMoreInfo('type', $this->_atk__core__hintable_magic__type);
    }

    protected function _atk__core__hintable_magic__buildFullName(string $name): string
    {
        $cl = $this->_atk__core__hintable_magic__class;

        return (is_string($cl) ? $cl : get_class($cl)) . '::' . $name;
    }

    /**
     * @return mixed[]
     */
    public function __debugInfo(): array
    {
        throw $this->_atk__core__hintable_magic__createNotSupportedException();
    }

    public function __sleep(): array
    {
        throw $this->_atk__core__hintable_magic__createNotSupportedException();
    }

    public function __wakeup(): void
    {
        throw $this->_atk__core__hintable_magic__createNotSupportedException();
    }

    public function __clone()
    {
        throw $this->_atk__core__hintable_magic__createNotSupportedException();
    }

    /**
     * @return mixed
     */
    public function __invoke()
    {
        throw $this->_atk__core__hintable_magic__createNotSupportedException();
    }

    public function __isset(string $name): bool
    {
        throw $this->_atk__core__hintable_magic__createNotSupportedException();
    }

    /**
     * @param mixed $value
     */
    public function __set(string $name, $value): void
    {
        throw $this->_atk__core__hintable_magic__createNotSupportedException();
    }

    public function __unset(string $name): void
    {
        throw $this->_atk__core__hintable_magic__createNotSupportedException();
    }

    /**
     * @param mixed[] $args
     */
    public static function __callStatic(string $name, array $args): void
    {
        throw (new static(\stdClass::class, 'static'))->_atk__core__hintable_magic__createNotSupportedException();
    }

    public function __get(string $name): string
    {
        throw $this->_atk__core__hintable_magic__createNotSupportedException();
    }

    /**
     * @param mixed[] $args
     *
     * @return mixed
     */
    public function __call(string $name, array $args)
    {
        throw $this->_atk__core__hintable_magic__createNotSupportedException();
    }
}
