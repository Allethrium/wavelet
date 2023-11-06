<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Phpstan;

use PHPStan\Reflection\Annotations\AnnotationPropertyReflection;
use PHPStan\Reflection\ClassReflection;
use PHPStan\Type\Type;

class WrapPropertyReflection extends AnnotationPropertyReflection
{
    public function __construct(ClassReflection $declaringClass, Type $type)
    {
        parent::__construct($declaringClass, $type, $type, true, false);
    }
}
