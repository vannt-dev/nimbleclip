[CmdletBinding()]
param(
    [string]$Source = 'assets\branding\nimbleclip_icon_master.png'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$sourcePath = (Resolve-Path -LiteralPath $Source).Path

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies 'System.Drawing' -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;

public static class NimbleClipIconTools {
    public static Bitmap ExtractWhiteMark(Bitmap source) {
        var output = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb);
        for (int y = 0; y < source.Height; y++) {
            for (int x = 0; x < source.Width; x++) {
                Color pixel = source.GetPixel(x, y);
                int minimum = Math.Min(pixel.R, Math.Min(pixel.G, pixel.B));
                int alpha = Math.Max(0, Math.Min(255, (minimum - 205) * 7));
                output.SetPixel(x, y, Color.FromArgb(alpha, 255, 255, 255));
            }
        }
        return output;
    }
}
'@

function Save-SquareImage {
    param(
        [System.Drawing.Image]$Image,
        [string]$Destination,
        [int]$Size
    )

    $directory = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    # Opaque output is required by the iOS App Store and prevents bicubic edge
    # sampling from introducing semi-transparent pixels at the corners.
    $bitmap = New-Object System.Drawing.Bitmap -ArgumentList `
        $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($Image, 0, 0, $Size, $Size)
        $bitmap.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Save-ContainedMark {
    param(
        [System.Drawing.Bitmap]$Mark,
        [string]$Destination,
        [int]$CanvasSize,
        [int]$SafeSize
    )

    $bounds = [System.Drawing.Rectangle]::Empty
    for ($y = 0; $y -lt $Mark.Height; $y++) {
        for ($x = 0; $x -lt $Mark.Width; $x++) {
            if ($Mark.GetPixel($x, $y).A -gt 12) {
                if ($bounds.IsEmpty) {
                    $bounds = New-Object System.Drawing.Rectangle $x, $y, 1, 1
                } else {
                    $bounds = [System.Drawing.Rectangle]::Union(
                        $bounds,
                        (New-Object System.Drawing.Rectangle $x, $y, 1, 1)
                    )
                }
            }
        }
    }
    if ($bounds.IsEmpty) { throw 'No white foreground mark was detected.' }

    $scale = [Math]::Min($safeSize / $bounds.Width, $safeSize / $bounds.Height)
    $width = [int][Math]::Round($bounds.Width * $scale)
    $height = [int][Math]::Round($bounds.Height * $scale)
    $left = [int](($canvasSize - $width) / 2)
    $top = [int](($canvasSize - $height) / 2)

    $canvas = New-Object System.Drawing.Bitmap $canvasSize, $canvasSize
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.DrawImage(
            $Mark,
            (New-Object System.Drawing.Rectangle $left, $top, $width, $height),
            $bounds,
            [System.Drawing.GraphicsUnit]::Pixel
        )
        $canvas.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $canvas.Dispose()
    }
}

function Save-RoundImage {
    param(
        [System.Drawing.Image]$Image,
        [string]$Destination,
        [int]$Size
    )

    $canvas = New-Object System.Drawing.Bitmap $Size, $Size
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $path.AddEllipse(0, 0, $Size, $Size)
        $graphics.SetClip($path)
        $graphics.DrawImage($Image, 0, 0, $Size, $Size)
        $canvas.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $path.Dispose()
        $graphics.Dispose()
        $canvas.Dispose()
    }
}

function Get-SquarePngBytes {
    param([System.Drawing.Image]$Image, [int]$Size)

    $bitmap = New-Object System.Drawing.Bitmap -ArgumentList `
        $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $stream = New-Object System.IO.MemoryStream
    try {
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.DrawImage($Image, 0, 0, $Size, $Size)
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return $stream.ToArray()
    } finally {
        $stream.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Save-WindowsIcon {
    param([System.Drawing.Image]$Image, [string]$Destination)

    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $images = @($sizes | ForEach-Object { ,(Get-SquarePngBytes -Image $Image -Size $_) })
    $stream = [System.IO.File]::Open(
        (Join-Path $projectRoot $Destination),
        [System.IO.FileMode]::Create
    )
    $writer = New-Object System.IO.BinaryWriter $stream
    try {
        $writer.Write([UInt16]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]$sizes.Count)
        $offset = 6 + 16 * $sizes.Count
        for ($index = 0; $index -lt $sizes.Count; $index++) {
            $sizeByte = if ($sizes[$index] -eq 256) { 0 } else { $sizes[$index] }
            $writer.Write([byte]$sizeByte)
            $writer.Write([byte]$sizeByte)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([UInt16]1)
            $writer.Write([UInt16]32)
            $writer.Write([UInt32]$images[$index].Length)
            $writer.Write([UInt32]$offset)
            $offset += $images[$index].Length
        }
        foreach ($bytes in $images) { $writer.Write([byte[]]$bytes) }
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

$master = [System.Drawing.Bitmap]::FromFile($sourcePath)
try {
    $androidSizes = @{
        'mdpi' = 48
        'hdpi' = 72
        'xhdpi' = 96
        'xxhdpi' = 144
        'xxxhdpi' = 192
    }
    foreach ($density in $androidSizes.Keys) {
        Save-SquareImage -Image $master `
            -Destination "android\app\src\main\res\mipmap-$density\ic_launcher.png" `
            -Size $androidSizes[$density]
        Save-RoundImage -Image $master `
            -Destination "android\app\src\main\res\mipmap-$density\ic_launcher_round.png" `
            -Size $androidSizes[$density]
    }

    $mark = [NimbleClipIconTools]::ExtractWhiteMark($master)
    try {
        Save-ContainedMark -Mark $mark `
            -Destination 'android\app\src\main\res\drawable-nodpi\ic_launcher_foreground.png' `
            -CanvasSize 432 -SafeSize 252
        Save-ContainedMark -Mark $mark `
            -Destination 'android\app\src\main\res\drawable-nodpi\splash_mark.png' `
            -CanvasSize 256 -SafeSize 150
        Save-ContainedMark -Mark $mark `
            -Destination 'ios\Runner\Assets.xcassets\LaunchImage.imageset\LaunchImage.png' `
            -CanvasSize 128 -SafeSize 88
        Save-ContainedMark -Mark $mark `
            -Destination 'ios\Runner\Assets.xcassets\LaunchImage.imageset\LaunchImage@2x.png' `
            -CanvasSize 256 -SafeSize 176
        Save-ContainedMark -Mark $mark `
            -Destination 'ios\Runner\Assets.xcassets\LaunchImage.imageset\LaunchImage@3x.png' `
            -CanvasSize 384 -SafeSize 264
    } finally {
        $mark.Dispose()
    }

    $iosIcons = @{
        'Icon-App-20x20@1x.png' = 20
        'Icon-App-20x20@2x.png' = 40
        'Icon-App-20x20@3x.png' = 60
        'Icon-App-29x29@1x.png' = 29
        'Icon-App-29x29@2x.png' = 58
        'Icon-App-29x29@3x.png' = 87
        'Icon-App-40x40@1x.png' = 40
        'Icon-App-40x40@2x.png' = 80
        'Icon-App-40x40@3x.png' = 120
        'Icon-App-60x60@2x.png' = 120
        'Icon-App-60x60@3x.png' = 180
        'Icon-App-76x76@1x.png' = 76
        'Icon-App-76x76@2x.png' = 152
        'Icon-App-83.5x83.5@2x.png' = 167
        'Icon-App-1024x1024@1x.png' = 1024
    }
    foreach ($fileName in $iosIcons.Keys) {
        Save-SquareImage -Image $master `
            -Destination "ios\Runner\Assets.xcassets\AppIcon.appiconset\$fileName" `
            -Size $iosIcons[$fileName]
    }

    $webIcons = @{
        'web\favicon.png' = 32
        'web\icons\Icon-192.png' = 192
        'web\icons\Icon-512.png' = 512
        'web\icons\Icon-maskable-192.png' = 192
        'web\icons\Icon-maskable-512.png' = 512
    }
    foreach ($destination in $webIcons.Keys) {
        Save-SquareImage -Image $master -Destination $destination `
            -Size $webIcons[$destination]
    }

    foreach ($size in @(16, 32, 64, 128, 256, 512, 1024)) {
        Save-SquareImage -Image $master `
            -Destination "macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_$size.png" `
            -Size $size
    }

    Save-WindowsIcon -Image $master `
        -Destination 'windows\runner\resources\app_icon.ico'
} finally {
    $master.Dispose()
}

Write-Host 'Android, iOS, Web, macOS, and Windows icons generated successfully.' -ForegroundColor Green
