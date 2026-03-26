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
