<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Data;

use Atk4\Data\Exception;
use Atk4\Data\Model;
use Mvorisek\Atk4\Hintable\Core\MagicAbstract;

/**
 * @template TTargetClass of object
 * @template TReturnType
 *
 * @extends MagicAbstract<TTargetClass&Model, TReturnType>
 *
 * @property Model $_atk__core__hintable_magic__class
 */
class MagicModelField extends MagicAbstract
{
    public const TYPE_FIELD_NAME = 'field_n';

    protected function _atk__data__hintable_magic__getModelPropDef(string $name): HintablePropertyDef
    {
        $model = $this->_atk__core__hintable_magic__class->getModel(true);

        $hProps = \Closure::bind(static fn () => $model->getHintableProps(), null, $model)();

        if (!isset($hProps[$name])) {
            throw (new Exception('Hintable property is not defined'))
                ->addMoreInfo('property', $name)
                ->addMoreInfo('class', get_class($model));
        }

        return $hProps[$name];
    }

    public function __get(string $name): string
    {
        if ($this->_atk__core__hintable_magic__type === self::TYPE_FIELD_NAME) {
            return $this->_atk__data__hintable_magic__getModelPropDef($name)->fieldName;
        }

        throw $this->_atk__core__hintable_magic__createNotSupportedException();
    }
}
