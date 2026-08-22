<?php
declare(strict_types=1);

require __DIR__ . '/config/config.php';
require __DIR__ . '/lib/Helpers.php';
require __DIR__ . '/lib/Database.php';
require __DIR__ . '/lib/Auth.php';

Auth::boot();
Auth::logout();
Auth::boot();
Flash::add('success', 'You have been signed out.');
header('Location: ' . APP_BASE_URL . 'login.php');
exit;
