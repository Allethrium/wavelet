<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Data\ModelInheritance;

use Atk4\Data\Model;

/**
 * @property string $ax @Atk4\Field()
 * @property string $pk @Atk4\Field(field_name="id", visibility="protected_set")
 */
class A extends Model
{
    use BaseTrait {
        BaseTrait::init as private __base_init;
    }

    public $table = 'inheritance';

    protected function init(): void
    {
        parent::init();
        $this->__base_init();

        $this->addField($this->fieldName()->ax, ['type' => 'string', 'required' => true]);
    }
}
