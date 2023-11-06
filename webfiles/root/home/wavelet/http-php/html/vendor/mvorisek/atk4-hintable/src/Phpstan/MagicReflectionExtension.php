<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Phpstan;

use Mvorisek\Atk4\Hintable\Core\MagicAbstract;
use PHPStan\Analyser\OutOfClassScope;
use PHPStan\Reflection\ClassReflection;
use PHPStan\Reflection\MethodReflection;
use PHPStan\Reflection\MethodsClassReflectionExtension;
use PHPStan\Reflection\PropertiesClassReflectionExtension;
use PHPStan\Reflection\PropertyReflection;
use PHPStan\Type\Type;

class MagicReflectionExtension implements PropertiesClassReflectionExtension, MethodsClassReflectionExtension
{
    /**
     * @param class-string<object> $class
     */
    private function isA(ClassReflection $classReflection, string $class): bool
    {
        return $classReflection->getName() === $class || $classReflection->isSubclassOf($class);
    }

    private function getTargetClassType(ClassReflection $classReflection): Type
    {
        return $classReflection->getActiveTemplateTypeMap()->getType('TTargetClass');
    }

    private function getReturnTypeType(ClassReflection $classReflection): Type
    {
        return $classReflection->getActiveTemplateTypeMap()->getType('TReturnType');
    }

    public function hasProperty(ClassReflection $classReflection, string $propertyName): bool
    {
        if (!$this->isA($classReflection, MagicAbstract::class)) {
            return false;
        }

        $targetClassType = $this->getTargetClassType($classReflection);

        return $targetClassType->hasProperty($propertyName)->yes();
    }

    public function hasMethod(ClassReflection $classReflection, string $methodName): bool
    {
        if (!$this->isA($classReflection, MagicAbstract::class)) {
            return false;
        }

        $targetClassType = $this->getTargetClassType($classReflection);

        return $targetClassType->hasMethod($methodName)->yes();
    }

    public function getProperty(ClassReflection $classReflection, string $propertyName): PropertyReflection
    {
        $targetClassType = $this->getTargetClassType($classReflection);
        $returnTypeType = $this->getReturnTypeType($classReflection);

        $targetProperty = $targetClassType->getProperty($propertyName, new OutOfClassScope());

        return new WrapPropertyReflection($targetProperty->getDeclaringClass(), $returnTypeType);
    }

    public function getMethod(ClassReflection $classReflection, string $methodName): MethodReflection
    {
        $targetClassType = $this->getTargetClassType($classReflection);
        $returnTypeType = $this->getReturnTypeType($classReflection);

        $targetMethod = $targetClassType->getMethod($methodName, new OutOfClassScope());

        return new WrapMethodReflection($methodName, $targetMethod->getDeclaringClass(), $returnTypeType);
    }
}
