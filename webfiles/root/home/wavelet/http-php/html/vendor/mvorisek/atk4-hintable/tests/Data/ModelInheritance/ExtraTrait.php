<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Data\ModelInheritance;

/**
 * @property string $te @Atk4\Field()
 */
trait ExtraTrait
{
    use BaseTrait {
        BaseTrait::init as private __base_init;
    }

    protected function init(): void
    {
        if (!in_array(BaseTrait::class, class_uses(parent::class), true)) {
            $this->__base_init();
        }

        $this->addField($this->fieldName()->te, ['type' => 'string', 'required' => true]);
    }
}
