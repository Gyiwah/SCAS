<?php
/**
 * SCAS - QR code generator (ISO/IEC 18004), byte mode, error-correction
 * level M, versions 1 to 10. Renders to inline SVG.
 *
 * Written from the specification rather than pulled in as a dependency:
 * XAMPP's PHP build here has no GD extension, so a raster library would not
 * work anyway, and SVG scales to any projector or printer without blurring.
 *
 * The pipeline, in the order the standard defines it:
 *
 *   1. ENCODE      mode indicator + character count + payload bytes,
 *                  terminator, pad to a codeword boundary, then alternating
 *                  pad codewords 0xEC / 0x11.
 *   2. ERROR       Reed-Solomon over GF(256) with primitive polynomial
 *      CORRECTION  0x11D. Level M recovers roughly 15% damage, which matters
 *                  because these codes are displayed on projectors and
 *                  printed sheets in dusty classrooms.
 *   3. INTERLEAVE  data blocks then EC blocks, column-wise, so that physical
 *                  damage to one area of the symbol is spread across several
 *                  blocks instead of destroying one completely.
 *   4. LAYOUT      finder, separator, timing and alignment patterns, the dark
 *                  module, and the reserved format/version areas.
 *   5. PLACE       the bitstream in the boustrophedon (zigzag) order, from
 *                  the bottom-right corner, skipping the timing column.
 *   6. MASK        all eight mask patterns are applied and scored against the
 *                  four penalty rules; the lowest-scoring one wins. Masking
 *                  is what stops large blank runs or fake finder patterns
 *                  from confusing a scanner.
 *   7. FORMAT      format information (EC level + mask) protected by a
 *      INFO        BCH(15,5) code, written twice; version information
 *                  (BCH(18,6)) as well from version 7 upward.
 *
 * QrCode::selfTest() checks the implementation against published constants
 * from the standard. tools/qr_selftest.php runs it.
 */

declare(strict_types=1);

final class QrCode
{
    /** Error-correction level M, as the two bits used in the format string. */
    private const EC_LEVEL_M_BITS = 0b00;
    private const EC_LEVEL_L_BITS = 0b01;

    /**
     * Block structure for EC level M.
     * version => [EC codewords per block, [[block count, data codewords], ...]]
     */
    private const BLOCKS_M = [
        1  => [10, [[1, 16]]],
        2  => [16, [[1, 28]]],
        3  => [26, [[1, 44]]],
        4  => [18, [[2, 32]]],
        5  => [24, [[2, 43]]],
        6  => [16, [[4, 27]]],
        7  => [18, [[4, 31]]],
        8  => [22, [[2, 38], [2, 39]]],
        9  => [22, [[3, 36], [2, 37]]],
        10 => [26, [[4, 43], [1, 44]]],
    ];

    /** Alignment-pattern centre coordinates per version. */
    private const ALIGNMENT = [
        1  => [],
        2  => [6, 18],
        3  => [6, 22],
        4  => [6, 26],
        5  => [6, 30],
        6  => [6, 34],
        7  => [6, 22, 38],
        8  => [6, 24, 42],
        9  => [6, 26, 46],
        10 => [6, 28, 50],
    ];

    /** Remainder bits appended after the final codeword. */
    private const REMAINDER_BITS = [
        1 => 0, 2 => 7, 3 => 7, 4 => 7, 5 => 7, 6 => 7,
        7 => 0, 8 => 0, 9 => 0, 10 => 0,
    ];

    private static ?array $expTable = null;
    private static ?array $logTable = null;

    // =======================================================================
    // Public API
    // =======================================================================

    /**
     * Render $data as an SVG QR code.
     *
     * @param int $moduleSize pixels per module
     * @param int $margin     quiet-zone width in modules (the standard
     *                        requires at least 4; scanners fail without it)
     */
    public static function svg(
        string $data,
        int $moduleSize = 6,
        int $margin = 4,
        string $dark = '#111827',
        string $light = '#ffffff',
        string $title = 'QR code'
    ): string {
        $matrix = self::encode($data);
        $n      = count($matrix);
        $dim    = ($n + 2 * $margin) * $moduleSize;

        // One <path> for every dark module beats one <rect> each: the SVG is
        // several times smaller and renders faster.
        $path = '';
        for ($r = 0; $r < $n; $r++) {
            for ($c = 0; $c < $n; $c++) {
                if ($matrix[$r][$c] === 1) {
                    $x = ($c + $margin) * $moduleSize;
                    $y = ($r + $margin) * $moduleSize;
                    $path .= sprintf('M%d %dh%dv%dh-%dz', $x, $y, $moduleSize, $moduleSize, $moduleSize);
                }
            }
        }

        return sprintf(
            '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" '
            . 'role="img" aria-label="%s" shape-rendering="crispEdges">'
            . '<title>%s</title>'
            . '<rect width="%d" height="%d" fill="%s"/>'
            . '<path d="%s" fill="%s"/>'
            . '</svg>',
            $dim, $dim, $dim, $dim,
            htmlspecialchars($title, ENT_QUOTES),
            htmlspecialchars($title, ENT_QUOTES),
            $dim, $dim, $light,
            $path, $dark
        );
    }

    /**
     * Build the module matrix. 1 = dark, 0 = light.
     * @return array<int, array<int, int>>
     */
    public static function encode(string $data, int $ecBits = self::EC_LEVEL_M_BITS): array
    {
        $version = self::chooseVersion($data);
        $bits    = self::buildBitstream($data, $version);
        $final   = self::interleave($bits, $version);

        [$matrix, $reserved] = self::buildFunctionPatterns($version);
        $matrix = self::placeData($matrix, $reserved, $final, $version);

        // Score all eight masks and keep the best.
        $best = null;
        $bestPenalty = PHP_INT_MAX;
        $bestMask = 0;
        for ($mask = 0; $mask < 8; $mask++) {
            $candidate = self::applyMask($matrix, $reserved, $mask);
            $candidate = self::placeFormatInfo($candidate, $ecBits, $mask, $version);
            $penalty   = self::penalty($candidate);
            if ($penalty < $bestPenalty) {
                $bestPenalty = $penalty;
                $best        = $candidate;
                $bestMask    = $mask;
            }
        }
        unset($bestMask);

        return $best;
    }

    // =======================================================================
    // Step 1 - data encoding
    // =======================================================================

    private static function dataCapacityCodewords(int $version): int
    {
        [, $groups] = self::BLOCKS_M[$version];
        $total = 0;
        foreach ($groups as [$count, $dataCw]) {
            $total += $count * $dataCw;
        }
        return $total;
    }

    private static function countBits(int $version): int
    {
        // Byte mode: 8 bits for versions 1-9, 16 bits for 10-40.
        return $version <= 9 ? 8 : 16;
    }

    private static function chooseVersion(string $data): int
    {
        $len = strlen($data);
        for ($v = 1; $v <= 10; $v++) {
            $needed = 4 + self::countBits($v) + 8 * $len;
            if (self::dataCapacityCodewords($v) * 8 >= $needed) {
                return $v;
            }
        }
        throw new InvalidArgumentException(
            'QrCode: payload of ' . $len . ' bytes exceeds the version 10 capacity supported here.'
        );
    }

    private static function buildBitstream(string $data, int $version): string
    {
        $capacityBits = self::dataCapacityCodewords($version) * 8;

        $bits  = '0100';                                              // byte mode
        $bits .= str_pad(decbin(strlen($data)), self::countBits($version), '0', STR_PAD_LEFT);
        for ($i = 0, $n = strlen($data); $i < $n; $i++) {
            $bits .= str_pad(decbin(ord($data[$i])), 8, '0', STR_PAD_LEFT);
        }

        // Terminator: up to four zero bits, but never past capacity.
        $bits .= str_repeat('0', min(4, $capacityBits - strlen($bits)));

        // Pad to a whole codeword.
        if (strlen($bits) % 8 !== 0) {
            $bits .= str_repeat('0', 8 - (strlen($bits) % 8));
        }

        // Fill the remaining codewords with the two specified pad bytes.
        $pads = ['11101100', '00010001'];   // 0xEC, 0x11
        $i = 0;
        while (strlen($bits) < $capacityBits) {
            $bits .= $pads[$i % 2];
            $i++;
        }

        return $bits;
    }

    // =======================================================================
    // Step 2 - Reed-Solomon over GF(256)
    // =======================================================================

    private static function initGaloisField(): void
    {
        if (self::$expTable !== null) {
            return;
        }
        $exp = array_fill(0, 512, 0);
        $log = array_fill(0, 256, 0);

        $x = 1;
        for ($i = 0; $i < 255; $i++) {
            $exp[$i] = $x;
            $log[$x] = $i;
            $x <<= 1;
            if ($x & 0x100) {
                $x ^= 0x11D;          // primitive polynomial x^8+x^4+x^3+x^2+1
            }
        }
        for ($i = 255; $i < 512; $i++) {
            $exp[$i] = $exp[$i - 255];
        }

        self::$expTable = $exp;
        self::$logTable = $log;
    }

    private static function gfMul(int $a, int $b): int
    {
        if ($a === 0 || $b === 0) {
            return 0;
        }
        self::initGaloisField();
        return self::$expTable[(self::$logTable[$a] + self::$logTable[$b]) % 255];
    }

    /**
     * Generator polynomial for $n error-correction codewords:
     * (x - alpha^0)(x - alpha^1)...(x - alpha^(n-1)).
     *
     * The loop below builds the coefficients in ASCENDING power order
     * (poly[k] is the coefficient of x^k), so poly[0] ends up as the constant
     * term and poly[n] as the leading 1. errorCorrection() performs synthetic
     * division and needs the LEADING coefficient first, so the result is
     * reversed before returning. Getting this backwards produces a polynomial
     * that still looks plausible but yields wrong check codewords and
     * therefore unscannable symbols - it is exactly what the generator
     * polynomial assertion in selfTest() exists to catch.
     */
    private static function generatorPoly(int $n): array
    {
        self::initGaloisField();
        $poly = [1];
        for ($i = 0; $i < $n; $i++) {
            $next = array_fill(0, count($poly) + 1, 0);
            foreach ($poly as $j => $coeff) {
                $next[$j]     ^= self::gfMul($coeff, self::$expTable[$i]);
                $next[$j + 1] ^= $coeff;
            }
            $poly = $next;
        }
        return array_reverse($poly);   // descending powers, leading coefficient first
    }

    /** @param int[] $data @return int[] the EC codewords */
    private static function errorCorrection(array $data, int $ecCount): array
    {
        $gen       = self::generatorPoly($ecCount);
        $remainder = array_merge($data, array_fill(0, $ecCount, 0));

        for ($i = 0, $n = count($data); $i < $n; $i++) {
            $factor = $remainder[$i];
            if ($factor === 0) {
                continue;
            }
            foreach ($gen as $j => $g) {
                $remainder[$i + $j] ^= self::gfMul($g, $factor);
            }
        }
        return array_slice($remainder, count($data));
    }

    // =======================================================================
    // Step 3 - block splitting and interleaving
    // =======================================================================

    private static function interleave(string $bits, int $version): string
    {
        [$ecPerBlock, $groups] = self::BLOCKS_M[$version];

        // Bitstream -> codewords
        $codewords = [];
        for ($i = 0, $n = strlen($bits); $i < $n; $i += 8) {
            $codewords[] = bindec(substr($bits, $i, 8));
        }

        // Split into blocks and compute EC per block.
        $dataBlocks = [];
        $ecBlocks   = [];
        $offset     = 0;
        foreach ($groups as [$count, $dataCw]) {
            for ($b = 0; $b < $count; $b++) {
                $block        = array_slice($codewords, $offset, $dataCw);
                $offset      += $dataCw;
                $dataBlocks[] = $block;
                $ecBlocks[]   = self::errorCorrection($block, $ecPerBlock);
            }
        }

        // Interleave data codewords column-wise, then EC codewords.
        $out = '';
        $maxData = max(array_map('count', $dataBlocks));
        for ($i = 0; $i < $maxData; $i++) {
            foreach ($dataBlocks as $block) {
                if (isset($block[$i])) {
                    $out .= str_pad(decbin($block[$i]), 8, '0', STR_PAD_LEFT);
                }
            }
        }
        for ($i = 0; $i < $ecPerBlock; $i++) {
            foreach ($ecBlocks as $block) {
                if (isset($block[$i])) {
                    $out .= str_pad(decbin($block[$i]), 8, '0', STR_PAD_LEFT);
                }
            }
        }

        return $out . str_repeat('0', self::REMAINDER_BITS[$version]);
    }

    // =======================================================================
    // Step 4 - function patterns
    // =======================================================================

    private static function size(int $version): int
    {
        return 21 + 4 * ($version - 1);
    }

    /** @return array{0: array, 1: array} [matrix, reserved] */
    private static function buildFunctionPatterns(int $version): array
    {
        $size     = self::size($version);
        $matrix   = array_fill(0, $size, array_fill(0, $size, 0));
        $reserved = array_fill(0, $size, array_fill(0, $size, false));

        $placeFinder = static function (int $top, int $left) use (&$matrix, &$reserved, $size): void {
            for ($r = -1; $r <= 7; $r++) {
                for ($c = -1; $c <= 7; $c++) {
                    $rr = $top + $r;
                    $cc = $left + $c;
                    if ($rr < 0 || $rr >= $size || $cc < 0 || $cc >= $size) {
                        continue;
                    }
                    $inRing   = ($r >= 0 && $r <= 6 && ($c === 0 || $c === 6))
                             || ($c >= 0 && $c <= 6 && ($r === 0 || $r === 6));
                    $inCentre = ($r >= 2 && $r <= 4 && $c >= 2 && $c <= 4);
                    $matrix[$rr][$cc]   = ($inRing || $inCentre) ? 1 : 0;
                    $reserved[$rr][$cc] = true;    // includes the separator ring
                }
            }
        };

        $placeFinder(0, 0);
        $placeFinder(0, $size - 7);
        $placeFinder($size - 7, 0);

        // Timing patterns.
        for ($i = 8; $i < $size - 8; $i++) {
            $bit = ($i % 2 === 0) ? 1 : 0;
            $matrix[6][$i]   = $bit;  $reserved[6][$i]   = true;
            $matrix[$i][6]   = $bit;  $reserved[$i][6]   = true;
        }

        // Alignment patterns, skipping the three that would sit on a finder.
        $centres = self::ALIGNMENT[$version];
        foreach ($centres as $r) {
            foreach ($centres as $c) {
                if (($r === 6 && $c === 6)
                 || ($r === 6 && $c === $size - 7)
                 || ($r === $size - 7 && $c === 6)) {
                    continue;
                }
                for ($dr = -2; $dr <= 2; $dr++) {
                    for ($dc = -2; $dc <= 2; $dc++) {
                        $ring = (abs($dr) === 2 || abs($dc) === 2 || ($dr === 0 && $dc === 0));
                        $matrix[$r + $dr][$c + $dc]   = $ring ? 1 : 0;
                        $reserved[$r + $dr][$c + $dc] = true;
                    }
                }
            }
        }

        // The always-dark module.
        $matrix[$size - 8][8]   = 1;
        $reserved[$size - 8][8] = true;

        // Reserve the format-information areas.
        for ($i = 0; $i <= 8; $i++) {
            if (!$reserved[8][$i])            { $reserved[8][$i] = true; }
            if (!$reserved[$i][8])            { $reserved[$i][8] = true; }
        }
        for ($i = 0; $i < 8; $i++) {
            $reserved[$size - 1 - $i][8] = true;
            $reserved[8][$size - 1 - $i] = true;
        }

        // Reserve the version-information areas (version 7 and above).
        if ($version >= 7) {
            for ($i = 0; $i < 18; $i++) {
                $r = intdiv($i, 3);
                $c = $size - 11 + ($i % 3);
                $reserved[$r][$c] = true;
                $reserved[$c][$r] = true;
            }
            $verBits = self::versionInfoBits($version);
            for ($i = 0; $i < 18; $i++) {
                $bit = ($verBits >> $i) & 1;
                $r = intdiv($i, 3);
                $c = $size - 11 + ($i % 3);
                $matrix[$r][$c] = $bit;
                $matrix[$c][$r] = $bit;
            }
        }

        return [$matrix, $reserved];
    }

    // =======================================================================
    // Step 5 - data placement
    // =======================================================================

    private static function placeData(array $matrix, array $reserved, string $bits, int $version): array
    {
        $size   = self::size($version);
        $len    = strlen($bits);
        $idx    = 0;
        $upward = true;

        for ($col = $size - 1; $col > 0; $col -= 2) {
            if ($col === 6) {
                $col--;              // the vertical timing pattern is not a data column
            }
            for ($i = 0; $i < $size; $i++) {
                $row = $upward ? ($size - 1 - $i) : $i;
                foreach ([$col, $col - 1] as $c) {
                    if ($reserved[$row][$c]) {
                        continue;
                    }
                    $matrix[$row][$c] = ($idx < $len) ? (int) $bits[$idx] : 0;
                    $idx++;
                }
            }
            $upward = !$upward;
        }
        return $matrix;
    }

    // =======================================================================
    // Step 6 - masking
    // =======================================================================

    private static function maskCondition(int $mask, int $r, int $c): bool
    {
        return match ($mask) {
            0 => ($r + $c) % 2 === 0,
            1 => $r % 2 === 0,
            2 => $c % 3 === 0,
            3 => ($r + $c) % 3 === 0,
            4 => (intdiv($r, 2) + intdiv($c, 3)) % 2 === 0,
            5 => (($r * $c) % 2) + (($r * $c) % 3) === 0,
            6 => (((($r * $c) % 2) + (($r * $c) % 3)) % 2) === 0,
            7 => (((($r + $c) % 2) + (($r * $c) % 3)) % 2) === 0,
            default => false,
        };
    }

    private static function applyMask(array $matrix, array $reserved, int $mask): array
    {
        $size = count($matrix);
        for ($r = 0; $r < $size; $r++) {
            for ($c = 0; $c < $size; $c++) {
                if (!$reserved[$r][$c] && self::maskCondition($mask, $r, $c)) {
                    $matrix[$r][$c] ^= 1;
                }
            }
        }
        return $matrix;
    }

    /** The four penalty rules from the standard. Lower is better. */
    private static function penalty(array $m): int
    {
        $size  = count($m);
        $score = 0;

        // Rule 1: runs of five or more identical modules in a row or column.
        for ($i = 0; $i < $size; $i++) {
            foreach ([true, false] as $isRow) {
                $run = 1;
                for ($j = 1; $j < $size; $j++) {
                    $cur  = $isRow ? $m[$i][$j]     : $m[$j][$i];
                    $prev = $isRow ? $m[$i][$j - 1] : $m[$j - 1][$i];
                    if ($cur === $prev) {
                        $run++;
                    } else {
                        if ($run >= 5) { $score += 3 + ($run - 5); }
                        $run = 1;
                    }
                }
                if ($run >= 5) { $score += 3 + ($run - 5); }
            }
        }

        // Rule 2: 2x2 blocks of one colour.
        for ($r = 0; $r < $size - 1; $r++) {
            for ($c = 0; $c < $size - 1; $c++) {
                $v = $m[$r][$c];
                if ($v === $m[$r][$c + 1] && $v === $m[$r + 1][$c] && $v === $m[$r + 1][$c + 1]) {
                    $score += 3;
                }
            }
        }

        // Rule 3: patterns that a scanner could mistake for a finder.
        $p1 = [1,0,1,1,1,0,1,0,0,0,0];
        $p2 = [0,0,0,0,1,0,1,1,1,0,1];
        for ($i = 0; $i < $size; $i++) {
            for ($j = 0; $j <= $size - 11; $j++) {
                $row = array_slice($m[$i], $j, 11);
                if ($row === $p1 || $row === $p2) {
                    $score += 40;
                }
                $col = [];
                for ($k = 0; $k < 11; $k++) {
                    $col[] = $m[$j + $k][$i];
                }
                if ($col === $p1 || $col === $p2) {
                    $score += 40;
                }
            }
        }

        // Rule 4: deviation from an even balance of dark and light.
        $dark = 0;
        foreach ($m as $row) {
            $dark += array_sum($row);
        }
        $percent = ($dark * 100) / ($size * $size);
        $score  += 10 * (int) floor(abs($percent - 50) / 5);

        return $score;
    }

    // =======================================================================
    // Step 7 - format and version information
    // =======================================================================

    /** BCH(15,5) with generator 0x537, XOR-masked with 0x5412. */
    public static function formatInfoBits(int $ecBits, int $mask): int
    {
        $data = (($ecBits & 0b11) << 3) | ($mask & 0b111);
        $rem  = $data << 10;
        for ($i = 14; $i >= 10; $i--) {
            if ($rem & (1 << $i)) {
                $rem ^= 0x537 << ($i - 10);
            }
        }
        return (($data << 10) | $rem) ^ 0x5412;
    }

    /** BCH(18,6) with generator 0x1F25. */
    public static function versionInfoBits(int $version): int
    {
        $rem = $version << 12;
        for ($i = 17; $i >= 12; $i--) {
            if ($rem & (1 << $i)) {
                $rem ^= 0x1F25 << ($i - 12);
            }
        }
        return ($version << 12) | $rem;
    }

    private static function placeFormatInfo(array $m, int $ecBits, int $mask, int $version): array
    {
        $size = self::size($version);
        $fmt  = self::formatInfoBits($ecBits, $mask);

        // Copy 1: around the top-left finder.
        for ($i = 0; $i <= 5; $i++) {
            $m[8][$i] = ($fmt >> $i) & 1;
        }
        $m[8][7] = ($fmt >> 6) & 1;
        $m[8][8] = ($fmt >> 7) & 1;
        $m[7][8] = ($fmt >> 8) & 1;
        for ($i = 9; $i <= 14; $i++) {
            $m[14 - $i][8] = ($fmt >> $i) & 1;
        }

        // Copy 2: split between the other two finders.
        for ($i = 0; $i <= 7; $i++) {
            $m[$size - 1 - $i][8] = ($fmt >> $i) & 1;
        }
        for ($i = 8; $i <= 14; $i++) {
            $m[8][$size - 15 + $i] = ($fmt >> $i) & 1;
        }

        $m[$size - 8][8] = 1;    // the dark module is never masked

        return $m;
    }

    // =======================================================================
    // Self-test against published constants
    // =======================================================================

    /** @return array<int, array{name: string, pass: bool, detail: string}> */
    public static function selfTest(): array
    {
        $results = [];

        $add = static function (string $name, bool $pass, string $detail) use (&$results): void {
            $results[] = ['name' => $name, 'pass' => $pass, 'detail' => $detail];
        };

        // Format strings published in ISO/IEC 18004 Table C.1.
        $m0 = self::formatInfoBits(self::EC_LEVEL_M_BITS, 0);
        $add(
            'Format info, level M, mask 0',
            $m0 === 0b101010000010010,
            sprintf('expected 101010000010010, got %015b', $m0)
        );

        $l0 = self::formatInfoBits(self::EC_LEVEL_L_BITS, 0);
        $add(
            'Format info, level L, mask 0',
            $l0 === 0b111011111000100,
            sprintf('expected 111011111000100, got %015b', $l0)
        );

        $l7 = self::formatInfoBits(self::EC_LEVEL_L_BITS, 7);
        $add(
            'Format info, level L, mask 7',
            $l7 === 0b110100101110110,
            sprintf('expected 110100101110110, got %015b', $l7)
        );

        // Version information published in Table D.1: 6 data bits followed by
        // 12 BCH check bits, 18 in total.
        $v7 = self::versionInfoBits(7);
        $add(
            'Version info, version 7',
            $v7 === 0b000111110010010100,
            sprintf('expected 000111110010010100, got %018b', $v7)
        );

        // Reed-Solomon generator polynomial for 10 EC codewords. The standard
        // gives its coefficients as alpha exponents
        // 0, 251, 67, 46, 61, 118, 70, 64, 94, 32, 45.
        self::initGaloisField();
        $gen      = self::generatorPoly(10);
        $expected = [0, 251, 67, 46, 61, 118, 70, 64, 94, 32, 45];
        $actual   = array_map(static fn(int $c): int => self::$logTable[$c], $gen);
        $add(
            'Reed-Solomon generator polynomial, 10 codewords',
            $actual === $expected,
            'exponents: ' . implode(',', $actual)
        );

        // Galois field sanity: alpha^255 wraps to 1.
        $add(
            'GF(256) field wraps at alpha^255',
            self::$expTable[255] === 1 && self::$expTable[8] === 0x1D,
            sprintf('exp[255]=%d, exp[8]=0x%02X (expect 1 and 0x1D)', self::$expTable[255], self::$expTable[8])
        );

        // Structural checks on a real encode.
        $token  = str_repeat('a1b2c3d4', 4);          // 32 chars, a realistic token
        $matrix = self::encode($token);
        $size   = count($matrix);
        $add(
            'A 32-character token encodes at version 3 (29x29)',
            $size === 29,
            'matrix is ' . $size . 'x' . $size
        );

        // The three finder patterns must be intact after masking.
        $finderOk = true;
        foreach ([[0, 0], [0, $size - 7], [$size - 7, 0]] as [$tr, $tc]) {
            for ($r = 0; $r < 7; $r++) {
                for ($c = 0; $c < 7; $c++) {
                    $ring   = ($r === 0 || $r === 6 || $c === 0 || $c === 6);
                    $centre = ($r >= 2 && $r <= 4 && $c >= 2 && $c <= 4);
                    $want   = ($ring || $centre) ? 1 : 0;
                    if ($matrix[$tr + $r][$tc + $c] !== $want) {
                        $finderOk = false;
                    }
                }
            }
        }
        $add('Finder patterns survive masking', $finderOk, $finderOk ? 'all three intact' : 'a finder was corrupted');

        // Timing patterns must alternate.
        $timingOk = true;
        for ($i = 8; $i < $size - 8; $i++) {
            if ($matrix[6][$i] !== ($i % 2 === 0 ? 1 : 0)) { $timingOk = false; }
            if ($matrix[$i][6] !== ($i % 2 === 0 ? 1 : 0)) { $timingOk = false; }
        }
        $add('Timing patterns alternate correctly', $timingOk, $timingOk ? 'row 6 and column 6 correct' : 'timing corrupted');

        // The dark module is mandatory.
        $add(
            'The mandatory dark module is set',
            $matrix[$size - 8][8] === 1,
            'module at (' . ($size - 8) . ',8)'
        );

        // Version selection boundaries. Version n holds:
        //   v1 16 data codewords, v3 44, v4 64, v5 86 (level M).
        // A payload of b bytes needs ceil((4 + 8 + 8b) / 8) codewords.
        $sizes = [
            14 => 21,   // 16 codewords exactly fills version 1
            40 => 29,   // 42 codewords -> version 3 (44), 29x29
            60 => 33,   // 62 codewords -> version 4 (64)
            70 => 37,   // 72 codewords -> version 5 (86)
        ];
        foreach ($sizes as $bytes => $expectedSize) {
            $got = count(self::encode(str_repeat('x', $bytes)));
            $add(
                sprintf('%d-byte payload encodes at %dx%d', $bytes, $expectedSize, $expectedSize),
                $got === $expectedSize,
                sprintf('got %dx%d', $got, $got)
            );
        }

        return $results;
    }
}
