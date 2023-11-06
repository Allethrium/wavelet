<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Data;

use Atk4\Core\Phpunit\TestCase;
use Atk4\Data\Exception;
use Atk4\Data\Model as AtkModel;
use Atk4\Data\Persistence;
use Mvorisek\Atk4\Hintable\Tests\Data\ModelInheritance as Mi;

/**
 * @coversDefaultClass \Mvorisek\Atk4\Hintable\Data\HintableModelTrait
 */
class HintableModelTest extends TestCase
{
    public function testFieldName(): void
    {
        $model = new Model\Simple();
        self::assertSame('simple', $model->table);
        self::assertSame('x', $model->fieldName()->x);
        self::assertSame('x', Model\Simple::hinting()->fieldName()->x);

        $model = new Model\Standard();
        self::assertSame('prefix_standard', $model->table);
        self::assertSame('x', $model->fieldName()->x);
        self::assertSame('yy', $model->fieldName()->y);
        self::assertSame('id', $model->fieldName()->id);
        self::assertSame('name', $model->fieldName()->_name);
        self::assertSame('simpleOne', $model->fieldName()->simpleOne);
        self::assertSame('simpleMany', $model->fieldName()->simpleMany);
    }

    public function testFieldNameUndeclaredException(): void
    {
        $model = new Model\Simple();

        $this->expectException(Exception::class);
        $this->expectExceptionMessage('Hintable property is not defined');
        $model->fieldName()->undeclared; // @phpstan-ignore-line
    }

    public function testParseDeclaredTwiceException(): void
    {
        /**
         * @property string $x @Atk4\Field()
         */
        $model = new class() extends AtkModel {};
        $model->invokeInit();

        /**
         * @property string $x @Atk4\Field()
         * @property string $x @Atk4\Field()
         */
        $model = new class() extends AtkModel {};

        $this->expectException(Exception::class);
        $this->expectExceptionMessage('Hintable property is defined twice within the same class');
        $model->invokeInit();
    }

    public function testParseInvalidOptionSyntaxException(): void
    {
        /**
         * @property string $x @Atk4\Field(="bar")
         */
        $model = new class() extends AtkModel {};

        $this->expectException(Exception::class);
        $this->expectExceptionMessage('Hintable property has invalid @Atk4\Field syntax');
        $model->invokeInit();
    }

    public function testParseInvalidOptionKeyException(): void
    {
        /**
         * @property string $x @Atk4\Field(foo="bar")
         */
        $model = new class() extends AtkModel {};

        $this->expectException(Exception::class);
        $this->expectExceptionMessage('Hintable property has invalid @Atk4\Field option');
        $model->invokeInit();
    }

    public function testParseInvalidOptionVisibilityException(): void
    {
        /**
         * @property string $x @Atk4\Field(visibility="publicc")
         */
        $model = new class() extends AtkModel {};

        $this->expectException(Exception::class);
        $this->expectExceptionMessage('Hintable property has invalid @Atk4\Field option');
        $model->invokeInit();
    }

    public function testInheritance(): void
    {
        $db = new Persistence\Array_();

        $model = new Mi\A($db);
        self::assertSame('inheritance', $model->table);
        self::assertSame('ax', $model->fieldName()->ax);
        self::assertSame('t', $model->fieldName()->t);
        self::assertSame('id', $model->fieldName()->pk);

        $model = new Mi\B($db);
        self::assertSame('inheritance', $model->table);
        self::assertSame('ax', $model->fieldName()->ax);
        self::assertSame('t', $model->fieldName()->t);
        self::assertSame('bx', $model->fieldName()->pk);
        self::assertSame('bx', $model->fieldName()->bx);
        self::assertSame('te', $model->fieldName()->te);

        /**
         * @property string $anx @Atk4\Field()
         */
        $model = new class($db) extends AtkModel {
            use Mi\ExtraTrait {
                Mi\ExtraTrait::init as private __extra_init;
            }

            public $table = 'anony';

            protected function init(): void
            {
                parent::init();
                $this->__extra_init();

                $this->addField($this->fieldName()->anx, ['type' => 'string', 'required' => true, 'default' => 'anxDef']); // @phpstan-ignore-line https://github.com/phpstan/phpstan/issues/7345
            }
        };
        self::assertSame('anony', $model->table);
        self::assertSame('t', $model->fieldName()->t);
        self::assertSame('te', $model->fieldName()->te);
        self::assertSame('anx', $model->fieldName()->anx); // @phpstan-ignore-line https://github.com/phpstan/phpstan/issues/7345
        self::assertSame('anxDef', $model->createEntity()->anx); // @phpstan-ignore-line https://github.com/phpstan/phpstan/issues/7345
    }

    /**
     * @param class-string|null           $scopeClass
     * @param class-string<AtkModel>      $modelClass
     * @param 'isset'|'get'|'set'|'unset' $operation
     *
     * @dataProvider provideVisibilityCases
     */
    public function testVisibility(?string $scopeClass, string $modelClass, string $propertyName, string $operation, ?string $expectedExceptionMessage): void
    {
        $model = new $modelClass();
        $model->invokeInit();
        $entity = $model->createEntity();
        $testCase = $this;
        \Closure::bind(static function () use ($entity, $testCase, $propertyName, $operation, $expectedExceptionMessage): void {
            $fieldName = $entity->fieldName()->{$propertyName};
            TestCase::assertSame($fieldName, $entity->getModel()->fieldName()->{$propertyName});
            $testValue = $entity->getModel()->getField($fieldName)->type === 'integer' ? 2 : '$v';

            if ($expectedExceptionMessage !== null) {
                $testCase->expectException(Exception::class);
                $testCase->expectExceptionMessage($expectedExceptionMessage);
            }

            if ($operation === 'isset') {
                TestCase::assertTrue(isset($entity->{$propertyName}));
            } elseif ($operation === 'get') {
                $entity->set($fieldName, $testValue);
                TestCase::assertSame($testValue, $entity->{$propertyName});
            } elseif ($operation === 'set') {
                $entity->{$propertyName} = $testValue;
                TestCase::assertSame($testValue, $entity->{$propertyName});
            } else {
                unset($entity->{$propertyName});
                TestCase::assertTrue(isset($entity->{$propertyName}));
                TestCase::assertNull($entity->{$propertyName});
            }
        }, null, $scopeClass)();
    }

    /**
     * @return iterable<list<mixed>>
     */
    public function provideVisibilityCases(): iterable
    {
        return [
            [AtkModel::class, AtkModel::class, 'id', 'get', null],
            [AtkModel::class, AtkModel::class, 'id', 'set', null],
            [AtkModel::class, AtkModel::class, 'id', 'isset', null],
            [AtkModel::class, AtkModel::class, 'id', 'unset', null],
            [Model\Simple::class, AtkModel::class, 'id', 'get', null],
            [Model\Simple::class, AtkModel::class, 'id', 'set', null],
            [Model\Simple::class, AtkModel::class, 'id', 'isset', null],
            [Model\Simple::class, AtkModel::class, 'id', 'unset', null],
            [get_class(new class() extends Model\Simple {}), AtkModel::class, 'id', 'get', null],
            [get_class(new class() extends Model\Simple {}), AtkModel::class, 'id', 'set', null],
            [null, AtkModel::class, 'id', 'get', null],
            [null, AtkModel::class, 'id', 'set', null],
            [null, AtkModel::class, 'id', 'isset', null],
            [null, AtkModel::class, 'id', 'unset', null],
            [Exception::class, AtkModel::class, 'id', 'get', null],
            [Exception::class, AtkModel::class, 'id', 'set', null],

            [Model\Simple::class, Model\Simple::class, 'id', 'get', null],
            [Model\Simple::class, Model\Simple::class, 'id', 'set', null],
            [get_class(new class() extends Model\Simple {}), Model\Simple::class, 'id', 'get', null],
            [get_class(new class() extends Model\Simple {}), Model\Simple::class, 'id', 'set', null],
            [null, Model\Simple::class, 'id', 'get', null],
            [null, Model\Simple::class, 'id', 'set', null],
            [Exception::class, Model\Simple::class, 'id', 'get', null],
            [Exception::class, Model\Simple::class, 'id', 'set', null],
            [AtkModel::class, Model\Simple::class, 'id', 'get', null],
            [AtkModel::class, Model\Simple::class, 'id', 'set', null],

            [Mi\A::class, Mi\A::class, 'pk', 'get', null],
            [Mi\A::class, Mi\A::class, 'pk', 'set', null],
            [Mi\B::class, Mi\A::class, 'pk', 'get', null],
            [Mi\B::class, Mi\A::class, 'pk', 'set', null],
            [null, Mi\A::class, 'pk', 'get', null],
            [null, Mi\A::class, 'pk', 'set', 'Cannot access write-protected hintable property ' . Mi\A::class . '::$pk'],
            [null, Mi\A::class, 'pk', 'isset', null],
            [null, Mi\A::class, 'pk', 'unset', 'Cannot access write-protected hintable property ' . Mi\A::class . '::$pk'],
            [Exception::class, Mi\A::class, 'pk', 'get', null],
            [Exception::class, Mi\A::class, 'pk', 'set', 'Cannot access write-protected hintable property ' . Mi\A::class . '::$pk'],
            [Exception::class, Mi\A::class, 'pk', 'isset', null],
            [Exception::class, Mi\A::class, 'pk', 'unset', 'Cannot access write-protected hintable property ' . Mi\A::class . '::$pk'],
            [AtkModel::class, Mi\A::class, 'pk', 'get', null],
            [AtkModel::class, Mi\A::class, 'pk', 'set', 'Cannot access write-protected hintable property ' . Mi\A::class . '::$pk'],

            [Mi\B::class, Mi\B::class, 'pk', 'get', null],
            [Mi\B::class, Mi\B::class, 'pk', 'set', null],
            [Mi\A::class, Mi\B::class, 'pk', 'get', null],
            [Mi\A::class, Mi\B::class, 'pk', 'set', null],
            [null, Mi\B::class, 'pk', 'get', null],
            [null, Mi\B::class, 'pk', 'set', 'Cannot access write-protected hintable property ' . Mi\B::class . '::$pk'],
            [Exception::class, Mi\B::class, 'pk', 'get', null],
            [Exception::class, Mi\B::class, 'pk', 'set', 'Cannot access write-protected hintable property ' . Mi\B::class . '::$pk'],
            [AtkModel::class, Mi\B::class, 'pk', 'get', null],
            [AtkModel::class, Mi\B::class, 'pk', 'set', 'Cannot access write-protected hintable property ' . Mi\B::class . '::$pk'],

            [Mi\Vis::class, Mi\Vis::class, 'vis', 'get', null],
            [Mi\Vis::class, Mi\Vis::class, 'vis', 'set', null],
            [Mi\Vis::class, Mi\Vis::class, 'vis', 'isset', null],
            [Mi\Vis::class, Mi\Vis::class, 'vis', 'unset', null],
            [Mi\Vis2::class, Mi\Vis::class, 'vis', 'get', null],
            [Mi\Vis2::class, Mi\Vis::class, 'vis', 'set', null],
            [Mi\Vis2::class, Mi\Vis::class, 'vis', 'isset', null],
            [Mi\Vis2::class, Mi\Vis::class, 'vis', 'unset', null],
            [Mi\Vis3::class, Mi\Vis::class, 'vis', 'get', null],
            [Mi\Vis3::class, Mi\Vis::class, 'vis', 'set', null],
            [Mi\Vis6::class, Mi\Vis::class, 'vis', 'get', null],
            [Mi\Vis6::class, Mi\Vis::class, 'vis', 'set', null],
            [get_class(new class() extends Mi\Vis {}), Mi\Vis::class, 'vis', 'get', null],
            [get_class(new class() extends Mi\Vis {}), Mi\Vis::class, 'vis', 'set', null],
            [null, Mi\Vis::class, 'vis', 'get', 'Cannot access protected hintable property ' . Mi\Vis::class . '::$vis'],
            [null, Mi\Vis::class, 'vis', 'set', 'Cannot access protected hintable property ' . Mi\Vis::class . '::$vis'],
            [null, Mi\Vis::class, 'vis', 'isset', 'Cannot access protected hintable property ' . Mi\Vis::class . '::$vis'],
            [null, Mi\Vis::class, 'vis', 'unset', 'Cannot access protected hintable property ' . Mi\Vis::class . '::$vis'],
            [Exception::class, Mi\Vis::class, 'vis', 'get', 'Cannot access protected hintable property ' . Mi\Vis::class . '::$vis'],
            [Exception::class, Mi\Vis::class, 'vis', 'set', 'Cannot access protected hintable property ' . Mi\Vis::class . '::$vis'],
            [Exception::class, Mi\Vis::class, 'vis', 'isset', 'Cannot access protected hintable property ' . Mi\Vis::class . '::$vis'],
            [Exception::class, Mi\Vis::class, 'vis', 'unset', 'Cannot access protected hintable property ' . Mi\Vis::class . '::$vis'],
            [AtkModel::class, Mi\Vis::class, 'vis', 'get', 'Cannot access protected hintable property ' . Mi\Vis::class . '::$vis'],
            [AtkModel::class, Mi\Vis::class, 'vis', 'set', 'Cannot access protected hintable property ' . Mi\Vis::class . '::$vis'],

            [Mi\Vis::class, Mi\Vis2::class, 'vis', 'get', null],
            [Mi\Vis::class, Mi\Vis2::class, 'vis', 'set', null],
            [Mi\Vis::class, Mi\Vis2::class, 'vis', 'isset', null],
            [Mi\Vis::class, Mi\Vis2::class, 'vis', 'unset', null],
            [null, Mi\Vis2::class, 'vis', 'get', 'Cannot access protected hintable property ' . Mi\Vis::class . '::$vis'],
            [null, Mi\Vis2::class, 'vis', 'set', 'Cannot access protected hintable property ' . Mi\Vis::class . '::$vis'],

            [Mi\Vis::class, Mi\Vis3::class, 'vis', 'get', null],
            [Mi\Vis::class, Mi\Vis3::class, 'vis', 'set', null],
            [Mi\Vis::class, Mi\Vis3::class, 'vis', 'isset', null],
            [Mi\Vis::class, Mi\Vis3::class, 'vis', 'unset', null],
            [null, Mi\Vis3::class, 'vis', 'get', null],
            [null, Mi\Vis3::class, 'vis', 'set', 'Cannot access write-protected hintable property ' . Mi\Vis3::class . '::$vis'],

            [Mi\Vis::class, Mi\Vis4::class, 'vis', 'get', null],
            [Mi\Vis::class, Mi\Vis4::class, 'vis', 'set', null],
            [null, Mi\Vis4::class, 'vis', 'get', null],
            [null, Mi\Vis4::class, 'vis', 'set', 'Cannot access write-protected hintable property ' . Mi\Vis3::class . '::$vis'],

            [Mi\Vis::class, Mi\Vis5::class, 'vis', 'get', null],
            [Mi\Vis::class, Mi\Vis5::class, 'vis', 'set', null],
            [Mi\Vis3::class, Mi\Vis5::class, 'vis', 'get', null],
            [Mi\Vis3::class, Mi\Vis5::class, 'vis', 'set', null],
            [null, Mi\Vis5::class, 'vis', 'get', null],
            [null, Mi\Vis5::class, 'vis', 'set', null],

            [Mi\Vis::class, Mi\Vis6::class, 'vis', 'get', null],
            [Mi\Vis::class, Mi\Vis6::class, 'vis', 'set', null],
            [Mi\Vis4::class, Mi\Vis6::class, 'vis', 'get', null],
            [Mi\Vis4::class, Mi\Vis6::class, 'vis', 'set', null],
            [null, Mi\Vis6::class, 'vis', 'get', null],
            [null, Mi\Vis6::class, 'vis', 'set', null],
        ];
    }
}
