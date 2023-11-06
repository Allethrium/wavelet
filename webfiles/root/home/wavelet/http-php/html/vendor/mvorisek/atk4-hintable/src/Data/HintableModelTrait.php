<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Data;

use Atk4\Data\Exception;
use Atk4\Data\Model;
use Mvorisek\Atk4\Hintable\Core\MagicAbstract;

/**
 * Adds hintable fields support to Model thru magic properties.
 *
 * How to define a hintable field:
 *   1. Define model field no later than in Model::init() like:
 *      <code>$m->addField('firstName');</code>
 *   2. Annotate model property in class phpdoc like:
 *      <code>@property string $firstName @Atk4\Field()</code>
 *      - use "field_name" parameter to change the target field name, by default mapped to the same name
 *      - use "visibility" parameter to limit the visibility, valid values are:
 *        - "public"        = default, no access restrictions
 *        - "protected_set" = property cannot be set outside the Model class
 *        - "protected"     = like protected property
 *      - regular class property MUST NOT be defined as there is no way to unset it when the class is created
 *        at least by "<code>ReflectionClass::newInstanceWithoutConstructor()</code>"
 *
 * Usecase - get/set field data:
 *   Simply use the magic property like a regular one, example:
 *   <code>$n = $m->firstName;</code>
 *   <code>$m->firstName = $n;</code>
 *
 * Usecase - get field name/definition:
 *   <code>$m->fieldName()->firstName;</code>
 *   <code>$m->getField($m->fieldName()->firstName);</code>
 */
trait HintableModelTrait
{
    /** @var HintablePropertyDef[] */
    private $_hintableProps;

    /**
     * @param class-string<Model> $className
     *
     * @return HintablePropertyDef[]
     */
    protected function createHintablePropsFromClassDoc(string $className): array
    {
        $this->assertIsModel();

        return HintablePropertyDef::createFromClassDoc($className);
    }

    /**
     * @return HintablePropertyDef[]
     */
    protected function getHintableProps(): array
    {
        $this->assertIsModel();

        if ($this->_hintableProps === null) {
            $cls = [];
            $cl = static::class;
            do {
                array_unshift($cls, $cl);
            } while ($cl = get_parent_class($cl));

            $defs = [];
            foreach ($cls as $cl) {
                $clDefs = $this->createHintablePropsFromClassDoc($cl);
                foreach ($clDefs as $clDef) {
                    // if property was defined in parent class already, simply override it
                    $clDef->sinceClassName = isset($defs[$clDef->name]) ? $defs[$clDef->name]->sinceClassName : $clDef->className;
                    $defs[$clDef->name] = $clDef;
                }
            }

            // IMPORTANT: check if all hintable property are not set, otherwise the magic functions will not work!
            foreach ($cls as $cl) {
                $thisProps = \Closure::bind(fn () => array_keys(get_object_vars($this)), $this, $cl)();
                foreach ($defs as $def) {
                    if (isset($thisProps[$def->name])) {
                        throw (new Exception('Hintable property must remain magical'))
                            ->addMoreInfo('property', $def->name)
                            ->addMoreInfo('class', $cl);
                    }
                }
            }

            $this->_hintableProps = $defs;
        }

        return $this->_hintableProps;
    }

    public function assertIsInitialized(): void
    {
        $this->getHintableProps(); // assert hintable phpdoc can parse
    }

    /**
     * @return class-string|null
     */
    private function getHintableScopeClassName(string $optimizeVisibility, bool $optimizeReadOnly): ?string
    {
        // optimization only
        if ($optimizeVisibility === HintablePropertyDef::VISIBILITY_PUBLIC
            || ($optimizeReadOnly && $optimizeVisibility === HintablePropertyDef::VISIBILITY_PROTECTED_SET)) {
            return null;
        }

        $limit = 2;
        $trace = null;
        $entryMethodName = null;
        $entryMethodNameRenamed = null;
        for ($i = 2;; ++$i) {
            if ($i >= $limit) {
                $limit *= 2;
                $trace = debug_backtrace(\DEBUG_BACKTRACE_PROVIDE_OBJECT | \DEBUG_BACKTRACE_IGNORE_ARGS, $limit);
                if ($entryMethodName === null) {
                    if (\PHP_MAJOR_VERSION === 7 && !str_starts_with($trace[1]['function'], '__hintable_')) {
                        // https://bugs.php.net/bug.php?id=69180
                        $entryMethodNameRenamed = [
                            '__isset' => '__hintable_isset',
                            '__get' => '__hintable_get',
                            '__set' => '__hintable_set',
                            '__unset' => '__hintable_unset',
                        ][$trace[1]['function']];
                    } else {
                        $entryMethodNameRenamed = $trace[1]['function'];
                    }
                    $entryMethodName = [
                        '__hintable_isset' => '__isset',
                        '__hintable_get' => '__get',
                        '__hintable_set' => '__set',
                        '__hintable_unset' => '__unset',
                    ][$entryMethodNameRenamed];
                }
            }
            if ($i >= count($trace)) {
                return null; // called directly from a global scope
            }
            $frame = $trace[$i];
            $frameFx = $frame['function'] ?? null;
            if (($frame['object'] ?? null) !== $this || ($frameFx !== $entryMethodName && $frameFx !== $entryMethodNameRenamed)) {
                return $frame['class'] ?? null;
            }
        }
    }

    public function __isset(string $name): bool
    {
        $hProps = $this->getModel(true)->getHintableProps();
        if (isset($hProps[$name])) {
            $hProp = $hProps[$name];
            $hProp->assertVisibility($this->getHintableScopeClassName($hProp->visibility, true), true);

            return true;
        }

        // default behaviour
        return isset($this->{$name});
    }

    /**
     * @return mixed
     */
    public function &__get(string $name)
    {
        $hProps = $this->getModel(true)->getHintableProps();
        if (isset($hProps[$name])) {
            $hProp = $hProps[$name];
            $hProp->assertVisibility($this->getHintableScopeClassName($hProp->visibility, true), true);

            if ($hProp->refType !== HintablePropertyDef::REF_TYPE_NONE) {
                $model = $this->ref($hProp->fieldName);

                if ($this->isEntity()) {
                    if ($hProp->refType === HintablePropertyDef::REF_TYPE_ONE) {
                        $model->assertIsEntity();
                    } else {
                        $model->assertIsModel();
                    }
                } else {
                    $model->assertIsModel();
                }

                // HasOne/ContainsOne::ref() method returns an unloaded entity when traversing entity not found
                if ($model->isEntity()) {
                    if (!$model->isLoaded()) {
                        $res = null;

                        return $res;
                    }
                }

                return $model;
            }

            $resNoRef = $this->get($hProp->fieldName);

            return $resNoRef;
        }

        // default behaviour
        return $this->{$name};
    }

    /**
     * @param mixed $value
     */
    public function __set(string $name, $value): void
    {
        $hProps = $this->getModel(true)->getHintableProps();
        if (isset($hProps[$name])) {
            $hProp = $hProps[$name];
            $hProp->assertVisibility($this->getHintableScopeClassName($hProp->visibility, false), false);

            $this->set($hProp->fieldName, $value);

            return;
        }

        // default behaviour
        $this->{$name} = $value;
    }

    public function __unset(string $name): void
    {
        $hProps = $this->getModel(true)->getHintableProps();
        if (isset($hProps[$name])) {
            $hProp = $hProps[$name];
            $hProp->assertVisibility($this->getHintableScopeClassName($hProp->visibility, false), false);

            $this->setNull($hProp->fieldName);

            return;
        }

        // default behaviour
        unset($this->{$name});
    }

    /**
     * Returns a magic class that pretends to be instance of this class, but in reality
     * only non-static hinting methods are supported.
     *
     * @return static
     */
    public static function hinting()
    {
        // @phpstan-ignore-next-line
        return new class(static::class, '') extends MagicAbstract {
            public function __call(string $name, array $args)
            {
                if (in_array($name, ['fieldName'], true)) {
                    $cl = (new \ReflectionClass($this->_atk__core__hintable_magic__class))->newInstanceWithoutConstructor();

                    return $cl->{$name}();
                }

                throw $this->_atk__core__hintable_magic__createNotSupportedException();
            }
        };
    }

    /**
     * Returns a magic class that pretends to be instance of this class, but in reality
     * any property returns its field name.
     *
     * @return static
     *
     * @phpstan-return MagicModelField<static, string>
     */
    public function fieldName()
    {
        $cl = MagicModelField::class;

        return new $cl($this, MagicModelField::TYPE_FIELD_NAME);
    }
}
