/*
script name: DesktopAHK/Capture.ahk
version: 0.3.0
purpose: Provides BMP and live window capture for the BarCode reader, including top-slice extraction for scaled panel solve.
dependencies: DesktopAHK/Config.ahk, DesktopAHK/Debug.ahk
 important assumptions: BMP inputs may contain a larger screenshot around the strip, and live capture relies on normal Win32 desktop/window capture availability.
protocol version: BC-Strip/1
framework module role: Capture abstraction
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Capture {
    static PreferredProcessNames := ["rift_x64.exe", "rift_x64", "Rift.exe", "Rift"]
    static PreferredWindowTitles := ["RIFT"]

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

    static AcquireFromWindow(hwnd, cropX := 0, cropY := 0, sourcePreference := "auto") {
        client := BC_Capture.GetClientRectOnScreen(hwnd)
        profile := BC_Config.ProfileP720A()
        isOccluded := false

        if (client.width <= cropX || client.height <= cropY) {
            throw Error("Requested live capture crop exceeds the RIFT client area.")
        }

        captureLeft := client.x + cropX
        captureTop := client.y + cropY
        captureWidth := client.width - cropX
        captureHeight := Min(client.height - cropY, Max(profile.BandHeight, BC_Config.SearchCaptureHeight))

        if (sourcePreference = "auto") {
            isOccluded := BC_Capture.IsBandRegionOccluded(hwnd, client, cropX, cropY, captureWidth, captureHeight)
            if (isOccluded) {
                if (BC_Capture.TryActivateWindow(hwnd)) {
                    Sleep 80
                    client := BC_Capture.GetClientRectOnScreen(hwnd)
                    captureLeft := client.x + cropX
                    captureTop := client.y + cropY
                    captureWidth := client.width - cropX
                    captureHeight := Min(client.height - cropY, Max(profile.BandHeight, BC_Config.SearchCaptureHeight))
                    isOccluded := BC_Capture.IsBandRegionOccluded(hwnd, client, cropX, cropY, captureWidth, captureHeight)
                }

                sourcePreference := isOccluded ? "printwindow" : "screen"
            } else {
                sourcePreference := "screen"
            }
        }

        if (sourcePreference != "screen") {
            try {
                image := BC_Capture.CaptureWindowClientRect(hwnd, cropX, cropY, captureWidth, captureHeight, client)
                return BC_Capture.AttachWindowMetadata(image, hwnd, client, captureLeft, captureTop, captureWidth, captureHeight, "printwindow-client")
            } catch as err {
                BC_Debug.Trace("capture.printwindow:fail=" err.Message "`r`n")
                if (sourcePreference = "printwindow") {
                    throw
                }
            }
        }

        image := BC_Capture.CaptureScreenRect(captureLeft, captureTop, captureWidth, captureHeight)
        return BC_Capture.AttachWindowMetadata(image, hwnd, client, captureLeft, captureTop, captureWidth, captureHeight, "screen-bitblt")
    }

    static FindRiftWindow() {
        activeHwnd := WinActive("A")
        if (activeHwnd && BC_Capture.IsPreferredWindow(activeHwnd) && BC_Capture.IsWindowUsable(activeHwnd)) {
            BC_Debug.Trace("capture.find:active=" BC_Capture.DescribeWindow(activeHwnd) "`r`n")
            return activeHwnd
        }

        bestHwnd := 0
        bestArea := -1
        traces := []

        for _, hwnd in WinGetList() {
            if !BC_Capture.IsPreferredWindow(hwnd) {
                continue
            }

            description := BC_Capture.DescribeWindow(hwnd)
            if !BC_Capture.IsWindowUsable(hwnd) {
                traces.Push("capture.find:skip=" description)
                continue
            }

            client := BC_Capture.GetClientRectOnScreen(hwnd)
            area := client.width * client.height
            traces.Push("capture.find:candidate=" description " area=" area)
            if (area > bestArea) {
                bestArea := area
                bestHwnd := hwnd
            }
        }

        if (traces.Length) {
            BC_Debug.Trace(BC_Debug.Join(traces, "`r`n") "`r`n")
        } else {
            BC_Debug.Trace("capture.find:no-preferred-window`r`n")
        }

        return bestHwnd
    }

    static IsPreferredWindow(hwnd) {
        try {
            processName := BC_Capture.NormalizeProcessName(WinGetProcessName("ahk_id " hwnd))
            for _, preferredProcessName in BC_Capture.PreferredProcessNames {
                if (processName = BC_Capture.NormalizeProcessName(preferredProcessName)) {
                    return true
                }
            }

            if (processName != "") {
                return false
            }

            title := StrLower(WinGetTitle("ahk_id " hwnd))
            for _, preferredTitle in BC_Capture.PreferredWindowTitles {
                if (preferredTitle != "" && InStr(title, StrLower(preferredTitle))) {
                    return true
                }
            }
        } catch {
            return false
        }

        return false
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

    static NormalizeProcessName(name) {
        normalized := StrLower(Trim(name))
        if (SubStr(normalized, -3) = ".exe") {
            normalized := SubStr(normalized, 1, StrLen(normalized) - 4)
        }
        return normalized
    }

    static DescribeWindow(hwnd) {
        try {
            processName := WinGetProcessName("ahk_id " hwnd)
            title := WinGetTitle("ahk_id " hwnd)
            client := BC_Capture.GetClientRectOnScreen(hwnd)
            return "hwnd=" hwnd " exe=" processName " title=" title " client=" client.width "x" client.height
        } catch {
            return "hwnd=" hwnd " unreadable"
        }
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

    static AttachWindowMetadata(image, hwnd, client, captureLeft, captureTop, captureWidth, captureHeight, sourceKind) {
        image.Hwnd := hwnd
        image.SourceLeft := captureLeft
        image.SourceTop := captureTop
        image.SourceWidth := captureWidth
        image.SourceHeight := captureHeight
        image.ClientRect := client
        image.SourceKind := sourceKind
        return image
    }

    static IsBandRegionOccluded(hwnd, client, cropX, cropY, captureWidth, captureHeight) {
        profile := BC_Config.ProfileP720A()
        rootHwnd := BC_Capture.GetRootWindow(hwnd)
        if !rootHwnd {
            rootHwnd := hwnd
        }

        sampleWidth := Min(captureWidth, Round(client.width * 0.72))
        sampleHeight := Min(captureHeight, profile.BandHeight)
        sampleXs := [8, Round(sampleWidth * 0.45), sampleWidth - 8]
        sampleYs := [8, sampleHeight - 8]

        for _, sampleY in sampleYs {
            for _, sampleX in sampleXs {
                absoluteX := client.x + cropX + BC_Capture.Clamp(sampleX, 0, captureWidth - 1)
                absoluteY := client.y + cropY + BC_Capture.Clamp(sampleY, 0, captureHeight - 1)
                pointRoot := BC_Capture.GetRootWindowAtPoint(absoluteX, absoluteY)
                if (pointRoot && pointRoot != rootHwnd) {
                    BC_Debug.Trace("capture.occluded:x=" absoluteX " y=" absoluteY " top=" pointRoot " target=" rootHwnd "`r`n")
                    return true
                }
            }
        }

        return false
    }

    static CaptureWindowClientRect(hwnd, cropX, cropY, captureWidth, captureHeight, client := "") {
        if !IsObject(client) {
            client := BC_Capture.GetClientRectOnScreen(hwnd)
        }

        fullImage := BC_Capture.CaptureWindowClient(hwnd, client.width, client.height)
        if (cropX = 0 && cropY = 0 && captureWidth = fullImage.Width && captureHeight = fullImage.Height) {
            return fullImage
        }

        return BC_Capture.CropRect(fullImage, cropX, cropY, captureWidth, captureHeight)
    }

    static CaptureWindowClient(hwnd, width, height) {
        if (width <= 0 || height <= 0) {
            throw Error("Window client capture dimensions must be positive.")
        }

        hdcWindow := 0
        hdcMem := 0
        hBitmap := 0
        hOldBitmap := 0

        try {
            hdcWindow := DllCall("GetDC", "Ptr", hwnd, "Ptr")
            if !hdcWindow {
                throw Error("GetDC failed for PrintWindow capture.")
            }

            hdcMem := DllCall("gdi32\CreateCompatibleDC", "Ptr", hdcWindow, "Ptr")
            if !hdcMem {
                throw Error("CreateCompatibleDC failed for PrintWindow capture.")
            }

            hBitmap := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", hdcWindow, "Int", width, "Int", height, "Ptr")
            if !hBitmap {
                throw Error("CreateCompatibleBitmap failed for PrintWindow capture.")
            }

            hOldBitmap := DllCall("gdi32\SelectObject", "Ptr", hdcMem, "Ptr", hBitmap, "Ptr")
            if !hOldBitmap {
                throw Error("SelectObject failed for PrintWindow capture.")
            }

            printFlags := 0x00000003
            printed := DllCall("PrintWindow", "Ptr", hwnd, "Ptr", hdcMem, "UInt", printFlags, "Int")
            if !printed {
                printFlags := 0x00000001
                printed := DllCall("PrintWindow", "Ptr", hwnd, "Ptr", hdcMem, "UInt", printFlags, "Int")
            }
            if !printed {
                throw Error("PrintWindow failed for the RIFT client.")
            }

            image := BC_Capture.ExtractBitmapPixels(hdcMem, hBitmap, width, height, "GetDIBits failed while copying the PrintWindow capture.")
            image.PrintFlags := printFlags
            return image
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
            if hdcWindow {
                DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdcWindow)
            }
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

            return BC_Capture.ExtractBitmapPixels(hdcMem, hBitmap, width, height, "GetDIBits failed while copying the live capture.")
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

    static ExtractBitmapPixels(hdc, hBitmap, width, height, failureMessage) {
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
            "Ptr", hdc,
            "Ptr", hBitmap,
            "UInt", 0,
            "UInt", height,
            "Ptr", dibPixels.Ptr,
            "Ptr", bitmapInfo.Ptr,
            "UInt", 0,
            "Int"
        )
        if (scanLines != height) {
            throw Error(failureMessage)
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
    }

    static GetRootWindow(hwnd) {
        if !hwnd {
            return 0
        }

        rootHwnd := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
        return rootHwnd ? rootHwnd : hwnd
    }

    static GetRootWindowAtPoint(x, y) {
        packedPoint := ((y & 0xFFFFFFFF) << 32) | (x & 0xFFFFFFFF)
        pointHwnd := DllCall("WindowFromPoint", "Int64", packedPoint, "Ptr")
        return BC_Capture.GetRootWindow(pointHwnd)
    }

    static TryActivateWindow(hwnd) {
        try {
            WinActivate("ahk_id " hwnd)
            return true
        } catch {
            return false
        }
    }

    static Clamp(value, minValue, maxValue) {
        if (value < minValue) {
            return minValue
        }
        if (value > maxValue) {
            return maxValue
        }
        return value
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
