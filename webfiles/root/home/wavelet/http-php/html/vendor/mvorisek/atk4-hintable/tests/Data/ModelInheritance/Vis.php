<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Data\ModelInheritance;

use Atk4\Data\Model;

/**
 * @property string $vis @Atk4\Field(visibility="protected")
 */
class Vis extends Model
{
    protected function init(): void
    {
        parent::init();

        $this->addField($this->fieldName()->vis, ['type' => 'string', 'required' => true]);
    }

    public function &__get(string $name)
    {
        return parent::__get($name);
    }
}

class Vis2 extends Vis
{
    /**
     * @return mixed
     */
    private function &__hintable_get(string $name)
    {
        return parent::__get($name);
    }

    public function &__get(string $name)
    {
        return $this->__hintable_get($name);
    }
}

/**
 * @property string $vis @Atk4\Field(visibility="protected_set")
 */
class Vis3 extends Vis2
{
    public function &__get(string $name)
    {
        return parent::__get($name);
    }
}

class Vis4 extends Vis3
{
}

/**
 * @property string $vis @Atk4\Field()
 */
class Vis5 extends Vis4
{
}

/**
 * @property string $vis @Atk4\Field(visibility="public")
 */
class Vis6 extends Vis5
{
    public function &__get(string $name)
    {
        return parent::__get($name);
    }
}
