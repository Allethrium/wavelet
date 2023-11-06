<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Data\Model;

use Atk4\Data\Model;

/**
 * @property string                       $x           @Atk4\Field()
 * @property string                       $y           @Atk4\Field(field_name="yy")
 * @property string                       $_name       @Atk4\Field(field_name="name") Property Model::name is defined, so we need to use different property name
 * @property \DateTimeImmutable           $dtImmutable @Atk4\Field()
 * @property \DateTimeInterface           $dtInterface @Atk4\Field()
 * @property \DateTime|\DateTimeImmutable $dtMulti     @Atk4\Field()
 * @property int                          $simpleOneId @Atk4\Field()
 * @property Simple                       $simpleOne   @Atk4\RefOne()
 * @property Simple                       $simpleMany  @Atk4\RefMany()
 */
class Standard extends Model
{
    public $table = 'prefix_standard';

    protected function init(): void
    {
        parent::init();

        $this->addField($this->fieldName()->x, ['type' => 'string', 'required' => true]);
        $this->addField($this->fieldName()->y, ['type' => 'string', 'required' => true]);
        $this->addField($this->fieldName()->_name, ['type' => 'string', 'required' => true]);

        $this->addField($this->fieldName()->dtImmutable, ['type' => 'datetime', 'required' => true]);
        $this->addField($this->fieldName()->dtInterface, ['type' => 'datetime', 'required' => true]);
        $this->addField($this->fieldName()->dtMulti, ['type' => 'datetime', 'required' => true]);

        $this->addField($this->fieldName()->simpleOneId, ['type' => 'integer']);
        $this->hasOne($this->fieldName()->simpleOne, ['model' => [Simple::class], 'ourField' => $this->fieldName()->simpleOneId]);

        $this->hasMany($this->fieldName()->simpleMany, ['model' => [Simple::class], 'theirField' => Simple::hinting()->fieldName()->refId]);
    }
}
