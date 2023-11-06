<?php
require_once __DIR__ . '/vendor/autoload.php';

$app = new \Atk4\Ui\App('Wavelet Web UI');
$app->initLayout([\Atk4\Ui\Layout\Centered::class]);

\Atk4\Ui\HelloWorld::addTo($app);