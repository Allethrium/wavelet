<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Phpstan;

use PhpParser\Node\Expr\MethodCall;
use PhpParser\Node\Expr\StaticCall;
use PHPStan\Analyser\Scope;
use PHPStan\Reflection\MethodReflection;
use PHPStan\Reflection\ParametersAcceptorSelector;
use PHPStan\Type\Constant\ConstantArrayType;
use PHPStan\Type\Constant\ConstantIntegerType;
use PHPStan\Type\Constant\ConstantStringType;
use PHPStan\Type\DynamicMethodReturnTypeExtension;
use PHPStan\Type\DynamicStaticMethodReturnTypeExtension;
use PHPStan\Type\Generic\GenericClassStringType;
use PHPStan\Type\IntersectionType;
use PHPStan\Type\ObjectType;
use PHPStan\Type\StaticType;
use PHPStan\Type\Type;
use PHPStan\Type\TypeCombinator;
use PHPStan\Type\UnionType;

class SeedDmrtExtension implements DynamicMethodReturnTypeExtension, DynamicStaticMethodReturnTypeExtension
{
    /** @var class-string */
    protected string $className;
    protected string $methodName;
    protected bool $methodIsStatic;
    protected int $seedParamIndex;

    /**
     * @param class-string $className
     */
    public function __construct(string $className, string $methodName, int $seedParamIndex)
    {
        $methodRefl = new \ReflectionMethod($className, $methodName);

        $this->className = $methodRefl->getDeclaringClass()->getName();
        $this->methodName = $methodRefl->getName();
        $this->methodIsStatic = $methodRefl->isStatic();
        $this->seedParamIndex = $seedParamIndex;
    }

    /**
     * @return class-string
     */
    public function getClass(): string
    {
        return $this->className;
    }

    public function isMethodSupported(MethodReflection $methodReflection): bool
    {
        return $methodReflection->getName() === $this->methodName && !$this->methodIsStatic;
    }

    public function isStaticMethodSupported(MethodReflection $methodReflection): bool
    {
        return $methodReflection->getName() === $this->methodName && $this->methodIsStatic;
    }

    private function getZeroKeyValueType(ConstantArrayType $arrayType): ?Type
    {
        $zeroIntegerType = new ConstantIntegerType(0);

        foreach ($arrayType->getKeyTypes() as $i => $keyType) {
            if ($keyType->equals($zeroIntegerType)) {
                return $arrayType->getValueTypes()[$i];
            }
        }

        return null;
    }

    protected function getTypeFromSeed(Type $type, bool $fromZeroKeyValue = false): ?Type
    {
        if ($type instanceof UnionType) {
            $types = [];
            foreach ($type->getTypes() as $t) {
                $t = $this->getTypeFromSeed($t, $fromZeroKeyValue);
                if ($t !== null) {
                    $types[] = $t;
                }
            }

            return count($types) === 0 ? null : TypeCombinator::union(...$types);
        } elseif ($type instanceof IntersectionType) {
            $types = [];
            foreach ($type->getTypes() as $t) {
                $t = $this->getTypeFromSeed($t, $fromZeroKeyValue);
                if ($t !== null) {
                    $types[] = $t;
                }
            }

            return count($types) === 0 ? null : TypeCombinator::intersect(...$types);
        }

        if ($type instanceof ObjectType || $type instanceof StaticType) {
            return $type;
        } elseif (!$fromZeroKeyValue) {
            if ($type instanceof ConstantArrayType) {
                $zeroKeyValueType = $this->getZeroKeyValueType($type);
                if ($zeroKeyValueType !== null) {
                    return $this->getTypeFromSeed($zeroKeyValueType, true);
                }
            }
        } else {
            if ($type instanceof ConstantStringType) {
                return new ObjectType($type->getValue());
            } elseif ($type instanceof GenericClassStringType) {
                return $this->getTypeFromSeed($type->getGenericType(), true);
            }
        }

        return null; // not enought type info
    }

    /**
     * @param MethodCall|StaticCall $methodCall
     */
    public function getTypeFromMethodCall(
        MethodReflection $methodReflection,
        $methodCall,
        Scope $scope
    ): Type {
        $returnType = ParametersAcceptorSelector::selectFromArgs(
            $scope,
            $methodCall->getArgs(),
            $methodReflection->getVariants()
        )->getReturnType();
        if (count($methodCall->getArgs()) - 1 >= $this->seedParamIndex) {
            $paramType = $scope->getType($methodCall->getArgs()[$this->seedParamIndex]->value);
            $typeFromSeed = $this->getTypeFromSeed($paramType);
            if ($typeFromSeed !== null) {
                $res = TypeCombinator::intersect($typeFromSeed, $returnType);

                return $res;
            }
        }

        return $returnType;
    }

    public function getTypeFromStaticMethodCall(
        MethodReflection $methodReflection,
        StaticCall $methodCall,
        Scope $scope
    ): Type {
        return $this->getTypeFromMethodCall($methodReflection, $methodCall, $scope);
    }
}
