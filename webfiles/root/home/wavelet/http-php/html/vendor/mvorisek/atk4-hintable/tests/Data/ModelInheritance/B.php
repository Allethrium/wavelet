<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Data\ModelInheritance;

/**
 * @property string $bx @Atk4\Field()
 * @property string $pk @Atk4\Field(field_name="bx", visibility="protected_set")
 */
class B extends A
{
    use ExtraTrait {
        ExtraTrait::init as private __extra_init;
    }

    protected function init(): void
    {
        parent::init();
        $this->__extra_init();

        $this->addField($this->fieldName()->bx, ['type' => 'string', 'required' => true]);
    }
}
