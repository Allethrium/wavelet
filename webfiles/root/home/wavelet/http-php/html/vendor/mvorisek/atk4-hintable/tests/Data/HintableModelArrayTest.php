<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Tests\Data;

use Atk4\Core\Phpunit\TestCase;
use Atk4\Data\Exception;
use Atk4\Data\Model as AtkModel;
use Atk4\Data\Persistence;
use Mvorisek\Atk4\Hintable\Phpstan\PhpstanUtil;

/**
 * @coversDefaultClass \Mvorisek\Atk4\Hintable\Data\HintableModelTrait
 */
class HintableModelArrayTest extends TestCase
{
    protected function createPersistence(): Persistence
    {
        return new Persistence\Array_();
    }

    protected function createDatabaseForRefTest(): Persistence
    {
        $db = $this->createPersistence();

        $db->atomic(static function () use ($db) {
            $simple1 = (new Model\Simple($db))->createEntity()
                ->set(Model\Simple::hinting()->fieldName()->x, 'a')
                ->save();
            $simple2 = (new Model\Simple($db))->createEntity()
                ->set(Model\Simple::hinting()->fieldName()->x, 'b1')
                ->save();
            $simple3 = (new Model\Simple($db))->createEntity()
                ->set(Model\Simple::hinting()->fieldName()->x, 'b2')
                ->save();

            $standardTemplate = (new Model\Standard($db))->createEntity()
                ->set(Model\Standard::hinting()->fieldName()->x, 'xx')
                ->set(Model\Standard::hinting()->fieldName()->y, 'yy')
                ->set(Model\Standard::hinting()->fieldName()->_name, 'zz')
                ->set(Model\Standard::hinting()->fieldName()->dtImmutable, new \DateTime('2000-1-1 12:00:00 GMT'))
                ->set(Model\Standard::hinting()->fieldName()->dtInterface, new \DateTimeImmutable('2000-2-1 12:00:00 GMT'))
                ->set(Model\Standard::hinting()->fieldName()->dtMulti, new \DateTimeImmutable('2000-3-1 12:00:00 GMT'));
            for ($i = 0; $i < 10; ++$i) {
                (clone $standardTemplate)->save()->delete();
            }
            $standard11 = (clone $standardTemplate)
                ->set(Model\Standard::hinting()->fieldName()->simpleOneId, $simple1->id)
                ->save();
            $standard12 = (clone $standardTemplate)
                ->set(Model\Standard::hinting()->fieldName()->simpleOneId, $simple3->id)
                ->save();
            /* 13 - null simpleOneId */ (clone $standardTemplate)
                ->save();
            /* 14 - invalid simpleOneId */ (clone $standardTemplate)
                ->set(Model\Standard::hinting()->fieldName()->simpleOneId, 999)
                ->save();

            $simple1
                ->set(Model\Simple::hinting()->fieldName()->refId, $standard11->id)
                ->save();
            $simple2
                ->set(Model\Simple::hinting()->fieldName()->refId, $standard12->id)
                ->save();
            $simple3
                ->set(Model\Simple::hinting()->fieldName()->refId, $standard12->id)
                ->save();
        });

        return $db;
    }

    public function testRefBasic(): void
    {
        $db = $this->createDatabaseForRefTest();
        $model = new Model\Simple($db);

        $entity = $model->load(1);
        self::assertSame(1, $entity->getId());
        self::assertSame(1, $entity->id);
        self::assertSame('a', $entity->x);
        self::assertSame(11, $entity->refId);
        self::assertSame(11, $entity->ref->id);

        $entity = $model->load(2);
        self::assertSame('b1', $entity->x);
        self::assertSame(12, $entity->ref->id);

        $entity = $model->load(3);
        self::assertSame('b2', $entity->x);
        self::assertSame(12, $entity->ref->id);

        self::assertNull($model->tryLoad(4));
    }

    public function testRefWithoutPersistence(): void
    {
        $model = new Model\Standard();
        $model->invokeInit();

        $model->getReference($model->fieldName()->simpleOne)->checkTheirType = false;
        self::assertInstanceOf(Model\Simple::class, $model->simpleOne);

        // TODO atk4/data does not support traversing 1:N reference without persistence
        // self::assertInstanceOf(Model\Simple::class, $model->simpleMany);
    }

    /**
     * @param array<int> $expectedIds
     */
    protected static function assertModelIds(array $expectedIds, AtkModel $model): void
    {
        $resAssoc = array_map(static function (AtkModel $model) {
            return $model->id;
        }, iterator_to_array((clone $model)->setOrder($model->idField, 'asc')));

        self::assertSame(array_values($resAssoc), array_keys($resAssoc));
        self::assertSame(array_values($resAssoc), $expectedIds);
    }

    public function testRefOne(): void
    {
        $db = $this->createDatabaseForRefTest();
        $model = new Model\Standard($db);

        self::assertInstanceOf(Model\Simple::class, $model->simpleOne);
        self::assertInstanceOf(Model\Simple::class, $model->load(11)->simpleOne);
        self::assertSame(1, $model->load(11)->simpleOne->id);
        self::assertSame('a', $model->load(11)->simpleOne->x);
        self::assertSame(3, $model->load(12)->simpleOne->id);
        self::assertSame('b2', $model->load(12)->simpleOne->x);
        self::assertSame(3, $model->load(12)->simpleOne->getModel()->loadOne()->id);
        $simpleXName = $model->simpleOne->fieldName()->x;
        self::assertSame('b2', $model->load(12)->simpleOne->getModel()->loadBy($simpleXName, 'b2')->x);

        if ($db instanceof Persistence\Array_) { // TODO https://github.com/atk4/data/issues/997
            self::assertModelIds([1, 2, 3], $model->simpleOne);
        } else {
            self::assertModelIds([1, 3], $model->simpleOne);
        }
        self::assertModelIds([1], $model->load(11)->simpleOne->getModel());
        self::assertModelIds([3], $model->load(12)->simpleOne->getModel());
        self::assertSame(3, $model->load(12)->simpleOne->getModel()->loadBy($simpleXName, 'b2')->id);
        self::assertNull($model->load(11)->simpleOne->getModel()->tryLoadBy($simpleXName, 'b2'));
        self::assertModelIds([3], $model->load(12)->simpleOne->getModel()->loadBy($simpleXName, 'b2')->getModel());
    }

    public function testRefMany(): void
    {
        $db = $this->createDatabaseForRefTest();
        $model = new Model\Standard($db);

        self::assertInstanceOf(Model\Simple::class, $model->simpleMany);
        self::assertInstanceOf(Model\Simple::class, $model->load(11)->simpleMany);
        self::assertSame(1, $model->load(11)->simpleMany->loadOne()->id);
        self::assertSame('a', $model->load(11)->simpleMany->loadOne()->x);
        self::assertSame(2, $model->load(12)->simpleMany->load(2)->id);
        self::assertSame('b1', $model->load(12)->simpleMany->load(2)->x);
        self::assertSame(3, $model->load(12)->simpleMany->load(3)->id);
        self::assertSame('b2', $model->load(12)->simpleMany->load(3)->x);

        self::assertModelIds([1, 2, 3], $model->simpleMany);
        self::assertModelIds([1], $model->load(11)->simpleMany);
        self::assertModelIds([2, 3], $model->load(12)->simpleMany);
        $simpleXName = $model->simpleMany->fieldName()->x;
        self::assertSame(3, $model->load(12)->simpleMany->loadBy($simpleXName, 'b2')->id);
        self::assertNull($model->load(11)->simpleMany->tryLoadBy($simpleXName, 'b2'));
        self::assertModelIds([2, 3], $model->load(12)->simpleMany->loadBy($simpleXName, 'b2')->getModel());
    }

    public function testRefOneLoadOneException(): void
    {
        $db = $this->createDatabaseForRefTest();
        $model = new Model\Standard($db);
        $modelSimple = $model->simpleOne;

        $this->expectException(Exception::class);
        $this->expectExceptionMessage('more than one record can be loaded');
        $modelSimple->loadOne();
    }

    public function testRefManyLoadOneException(): void
    {
        $db = $this->createDatabaseForRefTest();
        $model = new Model\Standard($db);
        $modelSimple = $model->simpleMany;

        $this->expectException(Exception::class);
        $this->expectExceptionMessage('more than one record can be loaded');
        $modelSimple->loadOne();
    }

    public function testRefOneTraverseNull(): void
    {
        $db = $this->createDatabaseForRefTest();
        $model = new Model\Standard($db);

        $entity13 = $model->load(13);
        self::assertNull($entity13->simpleOne); // @phpstan-ignore-line

        $entityNull = $model->createEntity();
        self::assertNull($entityNull->simpleOne); // @phpstan-ignore-line
    }

    public function testRefOneTraverseInvalidException(): void
    {
        $db = $this->createDatabaseForRefTest();
        $model = new Model\Standard($db);
        $entity14 = $model->load(14);

        $this->expectException(Exception::class);
        $this->expectExceptionMessage('No record was found');
        PhpstanUtil::ignoreUnusedVariable($entity14->simpleOne);
    }

    public function testRefOneReverseTraverseNullException(): void
    {
        $db = $this->createDatabaseForRefTest();
        $model = new Model\Standard($db);
        $entityNull = $model->createEntity();

        self::assertNull($entityNull->simpleOne); // @phpstan-ignore-line

        $model->getReference($model->fieldName()->simpleOne)
            ->setDefaults(['ourField' => $model->fieldName()->id]);

        $this->expectException(Exception::class);
        $this->expectExceptionMessage('Unable to traverse on null value');
        PhpstanUtil::ignoreUnusedVariable($entityNull->simpleMany);
    }

    public function testRefManyTraverseNullException(): void
    {
        $db = $this->createDatabaseForRefTest();
        $model = new Model\Standard($db);
        $entityNull = $model->createEntity();

        $this->expectException(Exception::class);
        $this->expectExceptionMessage('Unable to traverse on null value');
        PhpstanUtil::ignoreUnusedVariable($entityNull->simpleMany);
    }

    public function testPhpstanModelIteratorAggregate(): void
    {
        $db = $this->createDatabaseForRefTest();
        $model = new Model\Simple($db);

        self::assertIsString($model->loadAny()->x); // @phpstan-ignore-line
        foreach ($model as $modelItem) {
            self::assertIsString($modelItem->x); // @phpstan-ignore-line
        }
    }
}
