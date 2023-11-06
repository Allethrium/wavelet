<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Data;

use Atk4\Data\Exception;
use Atk4\Data\Model;

// @TODO use Doctrine Annotation? https://www.doctrine-project.org/projects/doctrine-annotations/en/latest/index.html#reading-annotations

/**
 * @phpstan-consistent-constructor
 */
class HintablePropertyDef
{
    /** No access restrictions */
    public const VISIBILITY_PUBLIC = 'public';
    /** Property cannot be set outside the Model class */
    public const VISIBILITY_PROTECTED_SET = 'protected_set';
    /** Like protected property */
    public const VISIBILITY_PROTECTED = 'protected';

    /** Field is not a reference */
    public const REF_TYPE_NONE = 0;
    public const REF_TYPE_ONE = 1;
    public const REF_TYPE_MANY = 2;

    /** @var array<string> */
    protected static $allowedVisibilities = [
        self::VISIBILITY_PUBLIC,
        self::VISIBILITY_PROTECTED_SET,
        self::VISIBILITY_PROTECTED,
    ];

    /** @var array<class-string<Model>, static[]> */
    private static $_cacheDefsByClass = [];

    /** @var class-string<Model> */
    public $className;
    /** @var class-string<Model> */
    public $sinceClassName;
    /** @var string */
    public $name;
    /** @var string */
    public $fieldName;
    /** @var string[] */
    public $allowedTypes;
    /** @var int */
    public $refType;
    /** @var string */
    public $visibility;

    /**
     * @param class-string<Model> $className
     * @param string[]            $allowedTypes
     */
    public function __construct(string $className, string $name, string $fieldName, array $allowedTypes)
    {
        $this->className = $className;
        $this->name = $name;
        $this->fieldName = $fieldName;
        $this->allowedTypes = $allowedTypes;
    }

    /**
     * @param class-string<Model> $className
     *
     * @return static[]
     */
    public static function createFromClassDoc(string $className): array
    {
        $classRefl = new \ReflectionClass($className);
        $className = $classRefl->getName();

        if (!isset(self::$_cacheDefsByClass[$className])) {
            $traitDefs = [];
            foreach (class_uses($className) as $traitName) {
                $traitDefsSub = static::createFromClassDoc($traitName);
                foreach ($traitDefsSub as $def) {
                    $traitDefs[$def->name] = $def;
                }
            }

            $classDefs = [];
            $classDocRaw = $classRefl->getDocComment();
            $classDoc = $classDocRaw !== false ? preg_replace('~\s+~', ' ', preg_replace('~^\s*(?:/\s*)?\*+(?:/\s*$)?|\s*\*+/\s*$~m', '', $classDocRaw)) : '';
            foreach (preg_split('~(?<!\w)(?=@property(?!\w))~', $classDoc) as $l) {
                $def = static::createFromClassDocLine($className, $l);
                if ($def !== null) {
                    if (isset($classDefs[$def->name])) {
                        throw (new Exception('Hintable property is defined twice within the same class'))
                            ->addMoreInfo('property', $def->name)
                            ->addMoreInfo('class', $className);
                    }

                    $classDefs[$def->name] = $def;
                }
            }

            $defs = [];
            foreach ($traitDefs as $def) {
                $defs[$def->name] = $def;
            }
            foreach ($classDefs as $def) {
                $defs[$def->name] = $def;
            }

            self::$_cacheDefsByClass[$className] = $defs;
        }

        $defs = [];
        foreach (self::$_cacheDefsByClass[$className] as $k => $def) {
            $defs[$k] = clone $def;
        }

        return $defs;
    }

    /**
     * @param class-string<Model> $className
     *
     * @return static|null
     */
    protected static function createFromClassDocLine(string $className, string $classDocLine): ?self
    {
        if (!preg_match('~^@property[ \t]+([^\$()]+?)[ \t]+\$([^ ]+)[ \t]+.*@Atk4\\\\(Field|RefOne|RefMany)\(((?:[^()"]+|="[^"]*")*)\)~s', $classDocLine, $matches)) {
            return null;
        }

        $allowedTypes = static::parseDocType($matches[1]);
        $refType = ['RefOne' => self::REF_TYPE_ONE, 'RefMany' => self::REF_TYPE_MANY][$matches[3]] ?? self::REF_TYPE_NONE;
        $opts = static::parseDocFieldOptions($matches[4]);

        $fieldName = null;
        $visibility = null;
        foreach ($opts as $k => $v) {
            if ($k === 'field_name') {
                $fieldName = $v;
            } elseif ($k === 'visibility' && in_array($v, static::$allowedVisibilities, true)) {
                $visibility = $v;
            } else {
                throw (new Exception('Hintable property has invalid @Atk4\\' . $matches[3] . ' option'))
                    ->addMoreInfo('key', $k)
                    ->addMoreInfo('value', $v);
            }
        }

        $def = new static($className, $matches[2], $fieldName ?? $matches[2], $allowedTypes);
        $def->refType = $refType;
        $def->visibility = $visibility ?? self::VISIBILITY_PUBLIC;

        return $def;
    }

    /**
     * @return string[]
     */
    protected static function parseDocType(string $doc): array
    {
        $types = [];
        foreach (preg_split('~(?:[^"\|]+|="[^"]*")*\K\|~', $doc) as $t) {
            if (substr($t, 0, 1) === '?') {
                $t = substr($t, 1);
                $types[] = 'null';
            }
            $types[] = $t;
        }

        return array_unique($types);
    }

    /**
     * @return string[]
     */
    protected static function parseDocFieldOptions(string $doc): array
    {
        if (trim($doc) === '') {
            return [];
        }

        $opts = [];
        foreach (preg_split('~(?:[^",]+|="[^"]*")*\K,~', $doc) as $opt) {
            if (!preg_match('~^([^"=]+)=(?:([^"=]+)|"(.*)")$~s', $opt, $matches)
                || ($matches[2] !== '' && $matches[2] !== (string) (int) $matches[2])) {
                throw (new Exception('Hintable property has invalid @Atk4\\Field syntax'))
                    ->addMoreInfo('value', $opt);
            }
            $opts[trim($matches[1])] = $matches[2] !== '' ? (int) $matches[2] : trim($matches[3]);
        }

        return $opts;
    }

    /**
     * @param class-string|null $scopeClassName
     */
    public function assertVisibility(?string $scopeClassName, bool $readOnly): void
    {
        if ($this->visibility === self::VISIBILITY_PUBLIC
            || ($readOnly && $this->visibility === self::VISIBILITY_PROTECTED_SET)
            || is_a($scopeClassName, $this->sinceClassName, true)) {
            return;
        }

        $visibilityDescribe = ($this->visibility === self::VISIBILITY_PROTECTED_SET ? 'write-' : '') . 'protected';

        throw new Exception('Cannot access ' . $visibilityDescribe . ' hintable property ' . $this->className . '::$' . $this->name);
    }
}
