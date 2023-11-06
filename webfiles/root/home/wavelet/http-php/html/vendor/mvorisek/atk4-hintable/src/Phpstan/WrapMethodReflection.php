<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Phpstan;

use PHPStan\Reflection\Annotations\AnnotationMethodReflection;
use PHPStan\Reflection\ClassReflection;
use PHPStan\Type\Type;

class WrapMethodReflection extends AnnotationMethodReflection
{
    public function __construct(string $name, ClassReflection $declaringClass, Type $returnType)
    {
        parent::__construct($name, $declaringClass, $returnType, [], false, false, null);
    }
}
