<?php

declare(strict_types=1);

/**
 * Generates every Android launcher icon from one source PNG.
 *
 *   php tool/generate_icons.php assets/branding/app_icon.png [full|emblem]
 *
 * Written against PHP's GD rather than pulling in `flutter_launcher_icons`
 * because GD is already on this machine and the package needs a `pub get` —
 * and because the adaptive foreground here needs a crop that the package
 * cannot express.
 *
 * Two variants, because Android's adaptive icon cannot show a full logo
 * lockup and the choice is a real one:
 *
 *   full    the whole logo, held inside the 72dp Android actually shows.
 *           Nothing is clipped on a squircle or rounded mask; a circle mask
 *           takes the corners. The wordmark is legible but small.
 *   emblem  the artwork above the wordmark, scaled by width so it fills the
 *           visible area. Reads clearly at 48dp, but drops the "Dacaam POS"
 *           text — which no launcher icon could render legibly anyway.
 *
 * The legacy icon and the Play Store image always use the whole logo — those
 * are never masked.
 *
 * The numbers that matter: an adaptive icon is a 108dp canvas of which only
 * the inner 72dp is ever visible, and a circular mask inscribes a 72dp circle
 * in that. Scaling artwork to the full 108 — the obvious first guess — throws
 * a third of it away.
 */

const DENSITIES = [
    'mdpi'    => 1.0,
    'hdpi'    => 1.5,
    'xhdpi'   => 2.0,
    'xxhdpi'  => 3.0,
    'xxxhdpi' => 4.0,
];

/** Where the wordmark band starts in the source, measured from its luminance. */
const EMBLEM_BOTTOM_RATIO = 0.570;

/** Brand orange. The adaptive background, and the colour behind the emblem. */
const BRAND_ORANGE = [0xF9, 0x73, 0x16];

$source = $argv[1] ?? 'assets/branding/app_icon.png';
$variant = $argv[2] ?? 'full';

if (!in_array($variant, ['full', 'emblem'], true)) {
    fwrite(STDERR, "Variant must be 'full' or 'emblem'\n");
    exit(1);
}
if (!is_file($source)) {
    fwrite(STDERR, "No such file: $source\n");
    exit(1);
}

$root = dirname(__DIR__);
$res = $root . '/android/app/src/main/res';

$logo = trimTransparent(loadPng($source));

echo "Source  : $source\n";
echo "Variant : $variant\n\n";

// ------------------------------------------------------- legacy icons

foreach (DENSITIES as $density => $scale) {
    $size = (int) round(48 * $scale);
    $dir = "$res/mipmap-$density";
    @mkdir($dir, 0777, true);

    save(fit($logo, $size, $size, 1.0), "$dir/ic_launcher.png");
    save(circleMask(fit($logo, $size, $size, 1.0)), "$dir/ic_launcher_round.png");

    echo "  mipmap-$density/ic_launcher.png          {$size}x{$size}\n";
}

// -------------------------------------------------- adaptive foreground

// Both variants are sized against the 72dp Android shows, not the 108dp
// canvas. `full` is square so it is fitted whole; `emblem` is wide and short,
// with empty corners a circular mask cannot damage, so it is fitted by width.
foreach (DENSITIES as $density => $scale) {
    $size = (int) round(108 * $scale);
    $dir = "$res/mipmap-$density";

    $fg = $variant === 'emblem'
        ? fitWidth(emblem($logo), $size, 74 / 108)
        : fit($logo, $size, $size, 72 / 108);

    save($fg, "$dir/ic_launcher_foreground.png");

    echo "  mipmap-$density/ic_launcher_foreground.png  {$size}x{$size}\n";
}

// ------------------------------------------------------ adaptive XML

@mkdir("$res/mipmap-anydpi-v26", 0777, true);

$xml = <<<XML
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>

XML;

file_put_contents("$res/mipmap-anydpi-v26/ic_launcher.xml", $xml);
file_put_contents("$res/mipmap-anydpi-v26/ic_launcher_round.xml", $xml);

@mkdir("$res/values", 0777, true);
file_put_contents("$res/values/ic_launcher_background.xml", <<<XML
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#F97316</color>
</resources>

XML);

echo "  mipmap-anydpi-v26/ic_launcher.xml\n";
echo "  values/ic_launcher_background.xml\n";

// --------------------------------------------------- Play Store image

$store = $root . '/build/play-store-icon-512.png';
@mkdir(dirname($store), 0777, true);
save(flatten(fit($logo, 512, 512, 1.0)), $store);
echo "\n  $store  512x512 (Play Console listing)\n";

echo "\nDone.\n";

// =========================================================== helpers

function loadPng(string $path): GdImage
{
    $im = imagecreatefrompng($path);
    if ($im === false) {
        fwrite(STDERR, "Could not read $path\n");
        exit(1);
    }
    imagealphablending($im, false);
    imagesavealpha($im, true);

    return $im;
}

/** Strips the transparent border so the artwork fills its own canvas. */
function trimTransparent(GdImage $im): GdImage
{
    $w = imagesx($im);
    $h = imagesy($im);
    $minX = $w;
    $minY = $h;
    $maxX = 0;
    $maxY = 0;

    for ($y = 0; $y < $h; $y++) {
        for ($x = 0; $x < $w; $x++) {
            if (((imagecolorat($im, $x, $y) >> 24) & 0x7F) < 100) {
                $minX = min($minX, $x);
                $maxX = max($maxX, $x);
                $minY = min($minY, $y);
                $maxY = max($maxY, $y);
            }
        }
    }

    if ($minX > $maxX) {
        return $im;
    }

    // Kept square about the content's own centre, so nothing shifts when it
    // is later scaled into a square canvas.
    $side = max($maxX - $minX, $maxY - $minY) + 1;
    $cx = (int) (($minX + $maxX) / 2);
    $cy = (int) (($minY + $maxY) / 2);

    return crop($im, $cx - intdiv($side, 2), $cy - intdiv($side, 2), $side, $side);
}

/**
 * The artwork above the wordmark band, as its own wide strip.
 *
 * Deliberately not padded to a square: padding first and scaling afterwards
 * is what made the first attempt come out a third of the size it should be.
 */
function emblem(GdImage $im): GdImage
{
    $w = imagesx($im);
    $bottom = (int) round(imagesy($im) * EMBLEM_BOTTOM_RATIO);

    $out = blank($w, $bottom);
    imagealphablending($out, false);
    imagecopy($out, $im, 0, 0, 0, 0, $w, $bottom);

    return $out;
}

/** Scales by width onto a square canvas, keeping the aspect ratio. */
function fitWidth(GdImage $im, int $canvas, float $widthRatio): GdImage
{
    $targetW = (int) round($canvas * $widthRatio);
    $targetH = (int) round($targetW * imagesy($im) / imagesx($im));

    $work = $im;
    while (imagesx($work) > $targetW * 2) {
        $halfW = intdiv(imagesx($work), 2);
        $halfH = intdiv(imagesy($work), 2);
        $next = blank($halfW, $halfH);
        imagecopyresampled($next, $work, 0, 0, 0, 0, $halfW, $halfH, imagesx($work), imagesy($work));
        $work = $next;
    }

    $scaled = blank($targetW, $targetH);
    imagecopyresampled($scaled, $work, 0, 0, 0, 0, $targetW, $targetH, imagesx($work), imagesy($work));

    $out = blank($canvas, $canvas);
    imagecopy($out, $scaled, intdiv($canvas - $targetW, 2), intdiv($canvas - $targetH, 2), 0, 0, $targetW, $targetH);

    return $out;
}

function crop(GdImage $im, int $x, int $y, int $w, int $h): GdImage
{
    $out = blank($w, $h);
    imagecopy($out, $im, max(0, -$x), max(0, -$y), max(0, $x), max(0, $y), $w, $h);

    return $out;
}

/**
 * Scales into a square canvas, occupying `$inset` of it.
 *
 * Downscaled in halving steps: GD's one-shot resample of a 1200px logo to
 * 48px aliases badly, and a launcher icon is looked at every day.
 */
function fit(GdImage $im, int $w, int $h, float $inset): GdImage
{
    $target = (int) round(min($w, $h) * $inset);

    $work = $im;
    while (imagesx($work) > $target * 2) {
        $half = intdiv(imagesx($work), 2);
        $next = blank($half, $half);
        imagecopyresampled($next, $work, 0, 0, 0, 0, $half, $half, imagesx($work), imagesy($work));
        $work = $next;
    }

    $scaled = blank($target, $target);
    imagecopyresampled($scaled, $work, 0, 0, 0, 0, $target, $target, imagesx($work), imagesy($work));

    $out = blank($w, $h);
    imagecopy($out, $scaled, intdiv($w - $target, 2), intdiv($h - $target, 2), 0, 0, $target, $target);

    return $out;
}

function circleMask(GdImage $im): GdImage
{
    $w = imagesx($im);
    $h = imagesy($im);
    $out = blank($w, $h);

    $cx = ($w - 1) / 2;
    $cy = ($h - 1) / 2;
    $r = min($cx, $cy);

    imagealphablending($out, false);
    for ($y = 0; $y < $h; $y++) {
        for ($x = 0; $x < $w; $x++) {
            $d = sqrt(($x - $cx) ** 2 + ($y - $cy) ** 2);
            if ($d > $r) {
                continue;
            }

            $c = imagecolorat($im, $x, $y);
            $alpha = ($c >> 24) & 0x7F;

            // One pixel of feathering, so the rim is not a staircase.
            if ($d > $r - 1) {
                $alpha = min(127, (int) round($alpha + (127 - $alpha) * ($d - ($r - 1))));
            }

            imagesetpixel($out, $x, $y, ($alpha << 24) | ($c & 0xFFFFFF));
        }
    }

    return $out;
}

/** Play Store rejects transparency, so the logo is laid on its own orange. */
function flatten(GdImage $im): GdImage
{
    $w = imagesx($im);
    $h = imagesy($im);
    $out = imagecreatetruecolor($w, $h);

    imagefilledrectangle($out, 0, 0, $w, $h, imagecolorallocate($out, ...BRAND_ORANGE));
    imagealphablending($out, true);
    imagecopy($out, $im, 0, 0, 0, 0, $w, $h);
    imagealphablending($out, false);
    imagesavealpha($out, false);

    return $out;
}

function blank(int $w, int $h): GdImage
{
    $im = imagecreatetruecolor($w, $h);
    imagealphablending($im, false);
    imagesavealpha($im, true);
    imagefilledrectangle($im, 0, 0, $w, $h, imagecolorallocatealpha($im, 0, 0, 0, 127));
    imagealphablending($im, true);

    return $im;
}

function save(GdImage $im, string $path): void
{
    imagealphablending($im, false);
    imagesavealpha($im, true);
    imagepng($im, $path, 9);
}
