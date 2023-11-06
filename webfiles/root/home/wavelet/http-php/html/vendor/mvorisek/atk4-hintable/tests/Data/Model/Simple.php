<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Data\Model;

use Atk4\Data\Model;

/**
 * @property string   $x     @Atk4\Field()
 * @property int      $refId @Atk4\Field()
 * @property Standard $ref   @Atk4\RefOne()
 */
class Simple extends Model
{
    public $table = 'simple';

    protected function init(): void
    {
        parent::init();

        $this->addField($this->fieldName()->x, ['type' => 'string', 'required' => true]);

        $this->addField($this->fieldName()->refId, ['type' => 'integer']);
        $this->hasOne($this->fieldName()->ref, ['model' => [Standard::class], 'ourField' => $this->fieldName()->refId]);
    }
}
