# Builds research-debt/thumbnail.png (144x144) and crops the client screenshots into
# dist/portal-images/*.png for the mod portal gallery. Needs only Windows .NET (no Pillow).
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$shots = Join-Path $root "tests\screenshots"
$out = Join-Path $root "dist\portal-images"
New-Item -ItemType Directory -Force $out | Out-Null

# --- thumbnail -------------------------------------------------------------
$bmp = New-Object System.Drawing.Bitmap 144, 144
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = "AntiAlias"
$g.TextRenderingHint = "AntiAliasGridFit"
$g.Clear([System.Drawing.Color]::FromArgb(255, 36, 36, 36))
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 255, 180, 60)), 4
$g.DrawRectangle($pen, 2, 2, 139, 139)
$big = New-Object System.Drawing.Font "Bahnschrift", 44, ([System.Drawing.FontStyle]::Bold)
$small = New-Object System.Drawing.Font "Bahnschrift", 13, ([System.Drawing.FontStyle]::Bold)
$orange = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 180, 60))
$grey = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 220, 220, 220))
$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment = "Center"; $fmt.LineAlignment = "Center"
$g.DrawString("x2.4", $big, $orange, (New-Object System.Drawing.RectangleF 0, 14, 144, 70), $fmt)
$g.DrawString("RESEARCH", $small, $grey, (New-Object System.Drawing.RectangleF 0, 88, 144, 20), $fmt)
$g.DrawString("DEBT", $small, $grey, (New-Object System.Drawing.RectangleF 0, 108, 144, 20), $fmt)
$g.Dispose()
$bmp.Save((Join-Path $root "research-debt\thumbnail.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "thumbnail.png written"

# --- crops -----------------------------------------------------------------
function Crop($name, $x, $y, $w, $h, $target) {
  $src = [System.Drawing.Image]::FromFile((Join-Path $shots $name))
  $rect = New-Object System.Drawing.Rectangle $x, $y, $w, $h
  $dst = New-Object System.Drawing.Bitmap $w, $h
  $gg = [System.Drawing.Graphics]::FromImage($dst)
  $gg.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $w, $h), $rect, [System.Drawing.GraphicsUnit]::Pixel)
  $gg.Dispose(); $src.Dispose()
  $dst.Save((Join-Path $out $target), [System.Drawing.Imaging.ImageFormat]::Png)
  $dst.Dispose()
  Write-Output "$target ($w x $h)"
}
Crop "rd-gui-1-main.png" 615 50 690 950 "1-window-overview.png"
Crop "rd-gui-6-request.png" 615 50 690 950 "2-ways-to-lower-and-requests.png"
Crop "rd-gui-2-values.png" 615 50 690 950 "3-archive-value-table.png"
Crop "rd-gui-4-scrolled-after-refresh.png" 615 50 690 950 "4-trades-and-log.png"
Crop "rd-gui-5-lab.png" 390 262 1140 460 "5-lab-panel.png"
