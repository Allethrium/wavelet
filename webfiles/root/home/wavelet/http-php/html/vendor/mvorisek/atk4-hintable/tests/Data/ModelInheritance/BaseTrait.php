<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Data\ModelInheritance;

/**
 * @property string $t @Atk4\Field()
 */
trait BaseTrait
{
    protected function init(): void
    {
        $this->addField($this->fieldName()->t, ['type' => 'string', 'required' => true]);
    }
}
