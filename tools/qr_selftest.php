<?php
declare(strict_types=1);
require __DIR__ . '/../app/lib/QrCode.php';

$results = QrCode::selfTest();
$pass = 0; $fail = 0;
foreach ($results as $r) {
    $ok = $r['pass'];
    $ok ? $pass++ : $fail++;
    printf("[%s] %-52s  %s\n", $ok ? 'PASS' : 'FAIL', $r['name'], $r['detail']);
}
printf("\n%d passed, %d failed\n", $pass, $fail);

if ($fail === 0) {
    file_put_contents(__DIR__ . '/qr_sample.svg', QrCode::svg('a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4', 8, 4));
    echo "Sample written to tools/qr_sample.svg - scan it with a phone to confirm.\n";
}
exit($fail === 0 ? 0 : 1);
