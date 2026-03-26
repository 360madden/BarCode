/*
script name: DesktopAHK/Capture.ahk
version: 0.2.0
purpose: Provides the minimum capture abstraction for the reader smoke by loading BMP inputs and returning a top search slice for scaled-panel solve when needed.
dependencies: DesktopAHK/Config.ahk, DesktopAHK/Debug.ahk
important assumptions: Live screen/window capture is intentionally deferred; this module loads 24-bit BMP inputs and keeps larger screenshots intact enough for scaled top-band detection.
protocol version: BC-Strip/1
framework module role: Capture abstraction
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Capture {
    static PreferredProcessNames := ["rift_x64.exe", "Rift.exe"]

    static AcquireFromBmp(path, cropX := 0, cropY := 0) {
        image := BC_Debug.ReadBmp24(path)
        profile := BC_Config.ProfileP720A()

        if (cropX = 0 && cropY = 0 && image.Width = profile.BandWidth && image.Height = profile.BandHeight) {
            return image
        }

        if (cropX < 0 || cropY < 0) {
            throw Error("Crop offsets must be non-negative")
        }

        if (cropX >= image.Width || cropY >= image.Height) {
            throw Error("Crop origin exceeds BMP bounds: input=" image.Width "x" image.Height " cropOrigin=" cropX "," cropY)
        }

        searchWidth := image.Width - cropX
        searchHeight := Min(image.Height - cropY, Max(profile.BandHeight, BC_Config.SearchCaptureHeight))
        return BC_Capture.CropRect(image, cropX, cropY, searchWidth, searchHeight)
    }

    static AcquireFromWindow(hwnd, cropX := 0, cropY := 0) {
        client := BC_Capture.GetClientRectOnScreen(hwnd)
        profile := BC_Config.ProfileP720A()

        if (client.width <= cropX || client.height <= cropY) {
            throw Error("Requested live capture crop exceeds the RIFT client area.")
        }

        captureLeft := client.x + cropX
        captureTop := client.y + cropY
        captureWidth := client.width - cropX
        captureHeight := Min(client.height - cropY, Max(profile.BandHeight, BC_Config.SearchCaptureHeight))

        image := BC_Capture.CaptureScreenRect(captureLeft, captureTop, captureWidth, captureHeight)
        image.Hwnd := hwnd
        image.SourceLeft := captureLeft
        image.SourceTop := captureTop
        image.SourceWidth := captureWidth
        image.SourceHeight := captureHeight
        image.ClientRect := client
        return image
    }

    static FindRiftWindow() {
        for _, processName in BC_Capture.PreferredProcessNames {
            activeHwnd := WinActive("ahk_exe " processName)
            if (activeHwnd && BC_Capture.IsWindowUsable(activeHwnd)) {
                return activeHwnd
            }
        }

        bestHwnd := 0
        bestArea := -1

        for _, processName in BC_Capture.PreferredProcessNames {
            hwndList := WinGetList("ahk_exe " processName)
            for _, hwnd in hwndList {
                if !BC_Capture.IsWindowUsable(hwnd) {
                    continue
                }
                client := BC_Capture.GetClientRectOnScreen(hwnd)
                area := client.width * client.height
                if (area > bestArea) {
                    bestArea := area
                    bestHwnd := hwnd
                }
            }
        }

        return bestHwnd
    }

    static IsWindowUsable(hwnd) {
        if !DllCall("IsWindowVisible", "Ptr", hwnd, "Int") {
            return false
        }

        try {
            if (WinGetMinMax("ahk_id " hwnd) = -1) {
                return false
            }
            client := BC_Capture.GetClientRectOnScreen(hwnd)
        } catch {
            return false
        }

        return client.width > 0 && client.height > 0
    }

    static GetClientRectOnScreen(hwnd) {
        rect := Buffer(16, 0)
        if !DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect.Ptr) {
            throw Error("GetClientRect failed.")
        }

        point := Buffer(8, 0)
        NumPut("Int", 0, point, 0)
        NumPut("Int", 0, point, 4)

        if !DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", point.Ptr) {
            throw Error("ClientToScreen failed.")
        }

        return {
            x: NumGet(point, 0, "Int"),
            y: NumGet(point, 4, "Int"),
            width: NumGet(rect, 8, "Int"),
            height: NumGet(rect, 12, "Int")
        }
    }

    static CaptureScreenRect(left, top, width, height) {
        if (width <= 0 || height <= 0) {
            throw Error("Capture rectangle must be positive.")
        }

        hdcScreen := 0
        hdcMem := 0
        hBitmap := 0
        hOldBitmap := 0

        try {
            hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
            if !hdcScreen {
                throw Error("GetDC failed.")
            }

            hdcMem := DllCall("gdi32\CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
            if !hdcMem {
                throw Error("CreateCompatibleDC failed.")
            }

            hBitmap := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", width, "Int", height, "Ptr")
            if !hBitmap {
                throw Error("CreateCompatibleBitmap failed.")
            }

            hOldBitmap := DllCall("gdi32\SelectObject", "Ptr", hdcMem, "Ptr", hBitmap, "Ptr")
            if !hOldBitmap {
                throw Error("SelectObject failed for live capture.")
            }

            rasterOp := 0x40CC0020
            if !DllCall(
                "gdi32\BitBlt",
                "Ptr", hdcMem,
                "Int", 0,
                "Int", 0,
                "Int", width,
                "Int", height,
                "Ptr", hdcScreen,
                "Int", left,
                "Int", top,
                "UInt", rasterOp
            ) {
                throw Error("BitBlt failed while capturing the RIFT client.")
            }

            paddedStride := ((width * 3) + 3) & ~3
            dibPixels := Buffer(paddedStride * height, 0)
            tightPixels := Buffer(width * height * 3, 0)
            bitmapInfo := Buffer(40, 0)
            NumPut("UInt", 40, bitmapInfo, 0)
            NumPut("Int", width, bitmapInfo, 4)
            NumPut("Int", -height, bitmapInfo, 8)
            NumPut("UShort", 1, bitmapInfo, 12)
            NumPut("UShort", 24, bitmapInfo, 14)
            NumPut("UInt", 0, bitmapInfo, 16)
            NumPut("UInt", dibPixels.Size, bitmapInfo, 20)

            scanLines := DllCall(
                "gdi32\GetDIBits",
                "Ptr", hdcMem,
                "Ptr", hBitmap,
                "UInt", 0,
                "UInt", height,
                "Ptr", dibPixels.Ptr,
                "Ptr", bitmapInfo.Ptr,
                "UInt", 0,
                "Int"
            )
            if (scanLines != height) {
                throw Error("GetDIBits failed while copying the live capture.")
            }

            row := 0
            while (row < height) {
                sourceOffset := row * paddedStride
                destOffset := row * width * 3
                columnOffset := 0
                while (columnOffset < (width * 3)) {
                    value := NumGet(dibPixels, sourceOffset + columnOffset, "UChar")
                    NumPut("UChar", value, tightPixels, destOffset + columnOffset)
                    columnOffset += 1
                }
                row += 1
            }

            return {
                Width: width,
                Height: height,
                Pixels: tightPixels
            }
        } finally {
            if hOldBitmap {
                DllCall("gdi32\SelectObject", "Ptr", hdcMem, "Ptr", hOldBitmap, "Ptr")
            }
            if hBitmap {
                DllCall("gdi32\DeleteObject", "Ptr", hBitmap)
            }
            if hdcMem {
                DllCall("gdi32\DeleteDC", "Ptr", hdcMem)
            }
            if hdcScreen {
                DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
            }
        }
    }

    static CropRect(image, cropX, cropY, cropWidth, cropHeight) {
        pixelBuffer := Buffer(cropWidth * cropHeight * 3, 0)
        row := 0

        while (row < cropHeight) {
            sourceOffset := ((cropY + row) * image.Width * 3) + (cropX * 3)
            destOffset := row * cropWidth * 3
            columnOffset := 0
            while (columnOffset < cropWidth * 3) {
                value := NumGet(image.Pixels, sourceOffset + columnOffset, "UChar")
                NumPut("UChar", value, pixelBuffer, destOffset + columnOffset)
                columnOffset += 1
            }
            row += 1
        }

        return {
            Width: cropWidth,
            Height: cropHeight,
            Pixels: pixelBuffer
        }
    }
}

; end-of-script marker comment
