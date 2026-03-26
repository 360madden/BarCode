/*
script name: DesktopAHK/Debug.ahk
version: 0.1.0
purpose: Provides BMP IO and compact reporting helpers for the BarCode AHK harness.
dependencies: AutoHotkey v2.0+
important assumptions: Supports uncompressed 24-bit BMP files only in phase 1.
protocol version: BC-Strip/1
framework module role: Debug and fixture support
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Debug {
    static TracePath() {
        return BC_Config.ReportDir "\trace.txt"
    }

    static Join(parts, delimiter := "") {
        output := ""
        for index, part in parts {
            if (index > 1) {
                output .= delimiter
            }
            output .= part
        }
        return output
    }

    static EnsureParentDir(path) {
        lastSlash := InStr(path, "\", , -1)
        if (lastSlash > 0) {
            dir := SubStr(path, 1, lastSlash - 1)
            DirCreate(dir)
        }
    }

    static WriteText(path, text) {
        BC_Debug.EnsureParentDir(path)
        if FileExist(path) {
            FileDelete(path)
        }
        FileAppend(text, path, "UTF-8")
    }

    static AppendText(path, text) {
        BC_Debug.EnsureParentDir(path)
        FileAppend(text, path, "UTF-8")
    }

    static Trace(text) {
        BC_Debug.AppendText(BC_Debug.TracePath(), text)
    }

    static Hex(bytes, startIndex := 1, count := 0) {
        parts := []
        limit := count > 0 ? Min(bytes.Length, startIndex + count - 1) : bytes.Length
        index := startIndex
        while (index <= limit) {
            parts.Push(Format("{:02X}", bytes[index]))
            index += 1
        }
        return parts.Length ? BC_Debug.Join(parts, " ") : ""
    }

    static WriteBmp24(path, width, height, pixelsBgrTopDown) {
        BC_Debug.Trace("debug.writebmp:start`r`n")
        rowStride := width * 3
        paddedStride := rowStride + Mod(4 - Mod(rowStride, 4), 4)
        pixelBytes := paddedStride * height
        fileSize := 54 + pixelBytes
        bmpBuffer := Buffer(fileSize, 0)

        NumPut("UChar", Ord("B"), bmpBuffer, 0)
        NumPut("UChar", Ord("M"), bmpBuffer, 1)
        NumPut("UInt", fileSize, bmpBuffer, 2)
        NumPut("UInt", 54, bmpBuffer, 10)
        NumPut("UInt", 40, bmpBuffer, 14)
        NumPut("Int", width, bmpBuffer, 18)
        NumPut("Int", height, bmpBuffer, 22)
        NumPut("UShort", 1, bmpBuffer, 26)
        NumPut("UShort", 24, bmpBuffer, 28)
        NumPut("UInt", 0, bmpBuffer, 30)
        NumPut("UInt", pixelBytes, bmpBuffer, 34)

        destOffset := 54
        row := 0
        while (row < height) {
            sourceRow := height - 1 - row
            sourceOffset := sourceRow * rowStride
            columnOffset := 0
            while (columnOffset < rowStride) {
                value := NumGet(pixelsBgrTopDown, sourceOffset + columnOffset, "UChar")
                NumPut("UChar", value, bmpBuffer, destOffset + columnOffset)
                columnOffset += 1
            }
            destOffset += paddedStride
            row += 1
        }
        BC_Debug.Trace("debug.writebmp:buffer-ready`r`n")

        BC_Debug.EnsureParentDir(path)
        file := FileOpen(path, "w")
        BC_Debug.Trace("debug.writebmp:file-open`r`n")
        file.RawWrite(bmpBuffer, fileSize)
        file.Close()
        BC_Debug.Trace("debug.writebmp:file-closed`r`n")
    }

    static ReadBmp24(path) {
        raw := FileRead(path, "RAW")
        if (StrGet(raw.Ptr, 2, "CP0") != "BM") {
            throw Error("Unsupported bitmap signature: " path)
        }

        pixelOffset := NumGet(raw, 10, "UInt")
        dibSize := NumGet(raw, 14, "UInt")
        if (dibSize != 40) {
            throw Error("Unsupported DIB header size: " dibSize)
        }

        width := NumGet(raw, 18, "Int")
        height := NumGet(raw, 22, "Int")
        planes := NumGet(raw, 26, "UShort")
        bpp := NumGet(raw, 28, "UShort")
        compression := NumGet(raw, 30, "UInt")

        if (planes != 1 || bpp != 24 || compression != 0) {
            throw Error("Only uncompressed 24-bit BMP is supported in phase 1.")
        }

        topDown := height < 0
        absHeight := Abs(height)
        rowStride := width * 3
        paddedStride := rowStride + Mod(4 - Mod(rowStride, 4), 4)
        pixels := Buffer(rowStride * absHeight, 0)

        row := 0
        while (row < absHeight) {
            sourceRow := topDown ? row : (absHeight - 1 - row)
            sourceOffset := pixelOffset + (sourceRow * paddedStride)
            destOffset := row * rowStride
            columnOffset := 0
            while (columnOffset < rowStride) {
                value := NumGet(raw, sourceOffset + columnOffset, "UChar")
                NumPut("UChar", value, pixels, destOffset + columnOffset)
                columnOffset += 1
            }
            row += 1
        }

        return {
            Width: width,
            Height: absHeight,
            Pixels: pixels
        }
    }
}

; end-of-script marker comment
