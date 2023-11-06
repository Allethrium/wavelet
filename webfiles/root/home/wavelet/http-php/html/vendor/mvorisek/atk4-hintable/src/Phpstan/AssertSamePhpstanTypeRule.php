<?php

declare(strict_types=1);

namespace Mvorisek\Atk4\Hintable\Phpstan;

use PhpParser\Node;
use PHPStan\Analyser\Scope;
use PHPStan\Rules\Rule;
use PHPStan\Rules\RuleErrorBuilder;
use PHPStan\Type\Constant\ConstantStringType;
use PHPStan\Type\VerbosityLevel;

/**
 * @implements Rule<Node\Expr\MethodCall>
 */
class AssertSamePhpstanTypeRule implements Rule
{
    public function getNodeType(): string
    {
        return Node\Expr\MethodCall::class;
    }

    private function getTraitName(): string
    {
        return AssertSamePhpstanTypeTrait::class;
    }

    /** @var array<class-string, array<string, bool>> */
    private static $_hasTraitCache = [];

    /**
     * Copied from https://github.com/atk4/core/blob/5aa6a4c3291564114252bc97f0c38660dba1da41/src/TraitUtil.php#L22 .
     *
     * @param class-string $class
     */
    private static function hasTrait($class, string $traitName): bool
    {
        if (!isset(self::$_hasTraitCache[$class][$traitName])) {
            $parentClass = get_parent_class($class);
            if ($parentClass !== false && self::hasTrait($parentClass, $traitName)) {
                self::$_hasTraitCache[$class][$traitName] = true;
            } else {
                $hasTrait = false;
                foreach (class_uses($class) as $useName) {
                    if ($useName === $traitName || self::hasTrait($useName, $traitName)) {
                        $hasTrait = true;

                        break;
                    }
                }

                self::$_hasTraitCache[$class][$traitName] = $hasTrait;
            }
        }

        return self::$_hasTraitCache[$class][$traitName];
    }

    /**
     * Based on https://github.com/phpstan/phpstan-src/blob/1.10.12/src/Rules/Debug/DumpTypeRule.php#L30
     * and https://github.com/phpstan/phpstan-src/blob/1.10.12/src/Rules/Debug/FileAssertRule.php#L63 .
     *
     * @param Node\Expr\MethodCall $node
     */
    public function processNode(Node $node, Scope $scope): array
    {
        if (!$node->name instanceof Node\Identifier || strcasecmp($node->name->name, 'assertSamePhpstanType') !== 0) {
            return [];
        }

        if (!self::hasTrait($scope->getClassReflection()->getName(), $this->getTraitName())) {
            return [];
        }

        if (count($node->getArgs()) !== 2) {
            return [
                RuleErrorBuilder::message(sprintf(
                    '%s() method call expects exactly 2 arguments.',
                    $this->getTraitName() . '::assertSamePhpstanType'
                ))
                    ->nonIgnorable()
                    ->build(),
            ];
        }

        $expectedTypeStringType = $scope->getType($node->getArgs()[0]->value);
        if (!$expectedTypeStringType instanceof ConstantStringType) {
            return [
                RuleErrorBuilder::message('Expected type must be a literal string.')->nonIgnorable()->build(),
            ];
        }

        $expectedTypeString = $expectedTypeStringType->getValue();
        $actualTypeString = $scope->getType($node->getArgs()[1]->value)->describe(VerbosityLevel::precise());
        if ($actualTypeString !== $expectedTypeString) {
            return [
                RuleErrorBuilder::message(sprintf('Expected type %s, actual: %s', $expectedTypeString, $actualTypeString))->nonIgnorable()->build(),
            ];
        }

        return [];
    }
}
