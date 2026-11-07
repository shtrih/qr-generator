# AGENTS.md

A graphical application for generating and reading QR codes. Written in Free Pascal (Lazarus / LCL) using the [QRCodeGenLib4Pascal](https://github.com/Xor-el/QRCodeGenLib4Pascal) and ZXing libraries. Released under the MIT license (see `LICENSE`).

## Language conventions

The user communicates in Russian, but the project is maintained in English: write code, comments, documentation, and this file in English.

## Project structure

- `qr_generator.lpr` — main program file (creates `TForm1`, runs the application).
- `unit1.pas` / `unit1.lfm` — the main form `TForm1`: the whole UI (text input, QR preview with download link, options, statistics) and the generation logic (`TForm1.UpdateQrCode`).
- `decodeform.pas` / `decodeform.lfm` — the modal "Decode QR Code" dialog `TDecodeForm`: loads an image (file dialog, drag & drop or clipboard) and decodes the QR code in it with the ZXing port; "Copy to Clipboard" / "Use in Generator" buttons.
- `qr_generator.lpi` — Lazarus project XML (packages, search paths, compiler options).
- `qr_generator.lps` — IDE session file (open files order etc.; do not touch).
- `qr_generator.ico` / `qr_generator.res` — application icon and compiled resource (`{$R *.res}` in the lpr).
- `backup/` — manual backups of `.lpi`/`.lps`; do not edit and do not include in builds (git-ignored).
- `QRCodeGenLib4Pascal/` — vendored copy of [QRCodeGenLib4Pascal](https://github.com/Xor-el/QRCodeGenLib4Pascal) (MIT), see "Library: QRCodeGenLib4Pascal" below. Committed to the repo without its upstream `.git`.
- `ZXing/` — vendored copy of the ZXing.Delphi FPC port (Apache 2.0), see "Library: ZXing (QR code reading)" below. Committed to the repo without its upstream `.git`.
- `patches/` — the local library patches as standalone diffs (`lcl-mode.patch`, `zxing-fpc.patch`), kept for re-applying after a re-clone.
- `.github/workflows/` — GitHub Actions CI: `build.yml` (build matrix + tag releases) and `install-fpc-lazarus.sh` (installer copied from the vendored library's own CI).
- Compiled units go to `lib\$(TargetCPU)-$(TargetOS)`; the binary is placed next to the project (both git-ignored).

## Build

From the CLI (no IDE). `lazbuild`/`fpc` are **not on PATH** on this machine; Lazarus 4.6 (FPC 3.2.2) lives in `E:\lazarus`, so use the full path:

```
E:/lazarus/lazbuild.exe qr_generator.lpi
```

Or via the Lazarus IDE (F9). The project is configured against the LCL package only; the target platform is Windows (`Win32\GraphicApplication=True`).

Build modes: **Default** (as above) and **Release** (`-O3`, stripped symbols — same output name). CI builds the Release mode; locally the Default mode stays active.

## CI

`.github/workflows/build.yml` runs on every push (any branch or tag), PRs and manual dispatch. It builds Windows x86_64 and Linux x86_64 (gtk2) Release binaries and uploads them as artifacts; a push of a `v*` tag additionally creates a GitHub Release with archives.

- FPC 3.2.2 + Lazarus 4.6 (branch `lazarus_4_6` of fpc/Lazarus) are installed by `.github/workflows/install-fpc-lazarus.sh` — a **verbatim copy** of `QRCodeGenLib4Pascal/.github/workflows/install-fpc-lazarus.sh`; re-copy it when the vendored library is updated. The script needs `bash` (Git Bash on Windows runners) and writes the lazbuild config itself.
- The library's `.inc` patch travels with the vendored sources, so CI needs no patching step.
- `qr_generator.res` is not committed: lazbuild regenerates it on build (verified locally).

## Library: QRCodeGenLib4Pascal

Integrated as a vendored copy in `QRCodeGenLib4Pascal/` (upstream `.git` removed when the project was put under git); the `.lpi` `SearchPaths/OtherUnitFiles` lists its `src\Interfaces`, `src\QRCodeGen` and `src\Utils` folders. Used units: `QlpIQrCode`, `QlpIQrSegment`, `QlpQrCode`, `QlpQrSegment`, `QlpQrSegmentMode`, `QlpQRCodeGenLibTypes`.

**Local patch (reapply after re-cloning/updating the vendored copy):** `QRCodeGenLib4Pascal\QRCodeGenLib\src\Include\QRCodeGenLibFPC.inc` has `{$DEFINE Framework_FCL}` commented out. Upstream forces FCL mode under FPC, where `TQRCodeGenLibBitmap` is an FPImage type; with it disabled the library compiles in LCL mode (`TQRCodeGenLibColor = TColor`, `ToBitmapImage` returns an LCL `TBitmap`) and feeds `TImage` directly. The patch is also stored as `patches/lcl-mode.patch`; after a fresh clone apply it with:

```
git -C QRCodeGenLib4Pascal apply ../patches/lcl-mode.patch
```

Key API facts (verified against the sources):
- `TQrSegment.MakeSegments(text, TEncoding.UTF8)` returns segments (an empty **nil** array for empty text — iterating it is safe, `Length` = 0).
- `TQrCode.EncodeSegments(segs, ecc, minVersion, maxVersion, mask, boostEcl)` — mask −1 = auto; raises `EDataTooLongQRCodeGenLibException` / `EArgumentInvalidQRCodeGenLibException` (base `EQRCodeGenLibException` in `QlpQRCodeGenLibTypes`).
- `IQrCode` exposes `Version`, `Mask`, `Size`, `GetModule`, colors, `ToBitmapImage(scale, border)` (caller frees the result) and `ToSvgString`/`ToSvgFile(border, filename)` which honor the set colors.
- The final (boosted) ECC level is **not** exposed by `IQrCode`; the app reproduces the library's boost rule by trial-encoding at the resulting version.

## Library: ZXing (QR code reading)

Integrated as a vendored copy in `ZXing/` — the `Lib/Classes` sources of the `v_3.0` branch of the [LongDirtyAnimAlf/ZXing.Delphi](https://github.com/LongDirtyAnimAlf/ZXing.Delphi) fork of [Spelt/ZXing.Delphi](https://github.com/Spelt/ZXing.Delphi) (Apache License 2.0, see `ZXing/LICENSE`), committed without its upstream `.git`. The `.lpi` `SearchPaths/OtherUnitFiles` lists `ZXing\Classes` and its eight subfolders — in **both** the base CompilerOptions and the Release build mode (independent duplicates). Used units: `ZXing.ScanManager`, `ZXing.BarCodeFormat`, `ZXing.ReadResult`.

**Local patch (reapply after re-cloning/updating the vendored copy):** `patches/zxing-fpc.patch` is a standalone diff against the upstream clone root; apply it in a fresh clone, then copy `Lib/Classes` over:

```
git -C ZXing.Delphi apply ../patches/zxing-fpc.patch
```

It makes two changes:
- `Filtering/ZXing.BaseLuminanceSource.pas`, `ZXing.RGBLuminanceSource.pas`, `ZXing.PlanarYUVLuminanceSource.pas`: the Delphi-only `UITypes` unit is wrapped in `{$ifndef FPC}` (only the non-compiled FMX branch needs it).
- `Common/ZXing.BarCodeFormat.pas`: `TBarcodeFormat` is renumbered to contiguous values 0..19. FPC's rtl-generics default comparers call `TypeInfo(T)` on generic type arguments, and sparse enums (the upstream Java-style powers of two, `QR_CODE = 2048` etc.) have no RTTI, so `TList<TBarcodeFormat>` (`TBarcodeFormatList`) fails to compile with "No type info available". The library never uses the numeric values (no `Ord()`/bitmask arithmetic — verified), so renumbering is safe.

Key API facts (verified against the sources and by a generate→decode round-trip test):
- `TScanManager.Create(TBarcodeFormat.QR_CODE, nil)` then `Scan(TBitmap): TReadResult` — takes an LCL `TBitmap` directly; **nil result = no code found**; decoding errors raise exceptions, so wrap `Scan` in try/except.
- `TReadResult.text` holds the decoded text (UTF-8 bytes under FPC). `rawBytes` are raw data codewords (mode/length headers included), **not** the parsed payload — compare `.text`, never `.rawBytes`.
- Passing `THints = nil` is fine when no hints are needed.
- The units compile in `{$mode delphi}`; calling them from `{$mode objfpc}` code (`decodeform.pas`) works as usual.

## Rules and gotchas

- **`.pas` / `.lfm` pairing**: the lpr sets `RequireDerivedFormResource:=True`, so the published fields of the form class in `.pas` must exactly match the objects in `.lfm`. When adding or removing components, edit both files consistently.
- `.lpi` is plain XML: text edits are fine, but preserve Lazarus's existing formatting and indentation.
- `.lps` is an IDE session file regenerated automatically; do not use it to infer project structure.
- Compiler mode `{$mode objfpc}{$H+}` (in every unit), strings are UTF-8.
- Hi-DPI is enabled: `Application.Scaled:=True`, `Scaled=True` in the `.lpi`, `DesignTimePPI=144` on the form. Keep the form scalable when editing its layout (avoid hard pixel sizes where adaptivity matters).
- Drag & drop of image files onto the two forms uses the LCL's `TCustomForm.AllowDropFiles` (set in both `.lfm` files) and the forms' `OnDropFiles` event. The win32 interface intercepts `WM_DROPFILES` itself (parses the files, calls `DragFinish`, delivers `OnDropFiles`) — a `message WM_DROPFILES` handler never fires unless the interface is built with `EnableWMDropFiles`, so do not hand-roll ShellAPI drop handling here.
- The `GolandProjects` folder is just a disk location; the project has nothing to do with Go.
