unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Spin, Math, CaptionFont, QlpIQrCode, QlpIQrSegment, QlpQrCode, QlpQrSegment,
  QlpQrSegmentMode, QlpQRCodeGenLibTypes;

type

  { TForm1 }

  TForm1 = class(TForm)
    lblText: TLabel;
    lblVersion: TLabel;
    memText: TMemo;
    lblTextHint: TPanel;
    lblTextHintText: TLabel;
    lblQr: TLabel;
    lblDownload: TLabel;
    Panel1: TPanel;
    pnlPreview: TScrollBox;
    imgPreview: TImage;
    lblEcc: TLabel;
    pnlEcc: TPanel;
    rbEccLow: TRadioButton;
    rbEccMedium: TRadioButton;
    rbEccQuartile: TRadioButton;
    rbEccHigh: TRadioButton;
    lblFormat: TLabel;
    pnlFormat: TPanel;
    rbBitmap: TRadioButton;
    rbVector: TRadioButton;
    lblBorder: TLabel;
    seBorder: TSpinEdit;
    lblModules: TLabel;
    lblScale: TLabel;
    seScale: TSpinEdit;
    lblPixels: TLabel;
    lblColors: TLabel;
    lblLightEq: TLabel;
    cbLight: TColorButton;
    lblDarkEq: TLabel;
    cbDark: TColorButton;
    lblMinEq: TLabel;
    seMinVer: TSpinEdit;
    lblMaxEq: TLabel;
    seMaxVer: TSpinEdit;
    lblMask: TLabel;
    seMask: TSpinEdit;
    lblMaskHint: TLabel;
    lblBoost: TLabel;
    chkBoost: TCheckBox;
    lblCaption: TLabel;
    chkCaption: TCheckBox;
    lblStats: TLabel;
    lblStatistics: TLabel;
    dlgColor: TColorDialog;
    procedure FormCreate(Sender: TObject);
  private
    FQRCode: IQrCode;
    FSegments: array of IQrSegment;
    procedure ControlChanged(Sender: TObject);
    procedure DownloadClick(Sender: TObject);
    procedure TextHintClick(Sender: TObject);
    function SelectedEcc: TQrCode.TEcc;
    function BoostedEcc(AVersion: Int32): TQrCode.TEcc;
    function CaptionLineWidthPix(ACanvas: TCanvas;
      const ALine: TCodePointArray; APx: Integer): Integer;
    procedure EllipsizeLine(var ALine: TCodePointArray; ACanvas: TCanvas;
      AMaxWidthPx, APx: Integer);
    function WrapCaptionLine(ACanvas: TCanvas; const ACodePoints: TCodePointArray;
      AMaxWidthPx, APx, AMaxLines: Integer): TCaptionLines;
    procedure BuildCaptionLines(ACanvas: TCanvas; ALines: TStrings;
      AMaxWidthPx, APx, AMaxLines: Integer; out AResult: TCaptionLines);
    procedure DrawCaptionLine(ACanvas: TCanvas; const ALine: TCodePointArray;
      AX, AY, APx: Integer);
    procedure ComposeCaption(ASource, ADest: TBitmap);
    procedure UpdateQrCode;
    procedure ShowError(const AMessage: String);
    procedure ClearPreview;
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

function EccLetter(AEcc: TQrCode.TEcc): String;
begin
  case AEcc of
    TQrCode.TEcc.eccLow: Result := 'L';
    TQrCode.TEcc.eccMedium: Result := 'M';
    TQrCode.TEcc.eccQuartile: Result := 'Q';
    else Result := 'H';
  end;
end;

function ModeName(AMode: TQrSegmentMode): String;
begin
  case AMode of
    TQrSegmentMode.qsmNumeric: Result := 'numeric';
    TQrSegmentMode.qsmAlphaNumeric: Result := 'alphanumeric';
    TQrSegmentMode.qsmByte: Result := 'byte';
    TQrSegmentMode.qsmKanji: Result := 'kanji';
    TQrSegmentMode.qsmEci: Result := 'eci';
    else Result := 'unknown';
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  memText.OnChange := @ControlChanged;
  rbEccLow.OnClick := @ControlChanged;
  rbEccMedium.OnClick := @ControlChanged;
  rbEccQuartile.OnClick := @ControlChanged;
  rbEccHigh.OnClick := @ControlChanged;
  rbBitmap.OnClick := @ControlChanged;
  rbVector.OnClick := @ControlChanged;
  seBorder.OnChange := @ControlChanged;
  seScale.OnChange := @ControlChanged;
  seMinVer.OnChange := @ControlChanged;
  seMaxVer.OnChange := @ControlChanged;
  seMask.OnChange := @ControlChanged;
  cbLight.OnColorChanged := @ControlChanged;
  cbDark.OnColorChanged := @ControlChanged;
  chkBoost.OnClick := @ControlChanged;
  chkCaption.OnClick := @ControlChanged;
  lblDownload.OnClick := @DownloadClick;
  lblTextHint.OnClick := @TextHintClick;
  UpdateQrCode;
end;

procedure TForm1.ControlChanged(Sender: TObject);
begin
  UpdateQrCode;
end;

procedure TForm1.TextHintClick(Sender: TObject);
begin
  memText.SetFocus;
end;

function TForm1.SelectedEcc: TQrCode.TEcc;
begin
  if rbEccMedium.Checked then
    Result := TQrCode.TEcc.eccMedium
  else if rbEccQuartile.Checked then
    Result := TQrCode.TEcc.eccQuartile
  else if rbEccHigh.Checked then
    Result := TQrCode.TEcc.eccHigh
  else
    Result := TQrCode.TEcc.eccLow;
end;

function TForm1.BoostedEcc(AVersion: Int32): TQrCode.TEcc;
const
  // same order as the library's boost loop; capacities only shrink as the
  // level rises, so the last fitting level is the highest fitting one
  EccOrder: array[0..3] of TQrCode.TEcc = (
    TQrCode.TEcc.eccLow, TQrCode.TEcc.eccMedium,
    TQrCode.TEcc.eccQuartile, TQrCode.TEcc.eccHigh);
var
  I: Integer;
begin
  Result := SelectedEcc;
  for I := Low(EccOrder) to High(EccOrder) do
  begin
    try
      TQrCode.EncodeSegments(FSegments, EccOrder[I], AVersion, AVersion, -1,
        False);
      Result := EccOrder[I];
    except
      Break;
    end;
  end;
end;

function TForm1.CaptionLineWidthPix(ACanvas: TCanvas;
  const ALine: TCodePointArray; APx: Integer): Integer;

  // width contributed by one run: pixel glyphs carry their own trailing
  // gap column, TrueType runs get a matching synthetic gap appended
  function RunWidth(AFrom, ATo: Integer; AKnown: Boolean): Integer;
  var
    J: Integer;
    S: String;
  begin
    if AKnown then
      Result := (ATo - AFrom) * CAPTION_GLYPH_ADVANCE * APx
    else
    begin
      S := '';
      for J := AFrom to ATo - 1 do
        S := S + CaptionCodePointToUtf8(ALine[J]);
      Result := ACanvas.TextWidth(S) + APx;
    end;
  end;

var
  I, LRunStart: Integer;
  LKnown: Boolean;
begin
  Result := 0;
  I := 0;
  while I < Length(ALine) do
  begin
    LKnown := CaptionGlyphIndex(ALine[I]) >= 0;
    LRunStart := I;
    while (I < Length(ALine)) and
          ((CaptionGlyphIndex(ALine[I]) >= 0) = LKnown) do
      Inc(I);
    Inc(Result, RunWidth(LRunStart, I, LKnown));
  end;
  if Result > 0 then
    Dec(Result, APx); // the trailing gap of the last glyph is not drawn
end;

procedure TForm1.EllipsizeLine(var ALine: TCodePointArray; ACanvas: TCanvas;
  AMaxWidthPx, APx: Integer);
begin
  if (Length(ALine) > 0) and (ALine[High(ALine)] = $2026) then
    Exit;
  SetLength(ALine, Length(ALine) + 1);
  ALine[High(ALine)] := $2026;
  // drop characters in front of the ellipsis until the line fits
  while (Length(ALine) > 1) and
        (CaptionLineWidthPix(ACanvas, ALine, APx) > AMaxWidthPx) do
  begin
    ALine[High(ALine) - 1] := ALine[High(ALine)];
    SetLength(ALine, Length(ALine) - 1);
  end;
end;

function TForm1.WrapCaptionLine(ACanvas: TCanvas;
  const ACodePoints: TCodePointArray; AMaxWidthPx, APx,
  AMaxLines: Integer): TCaptionLines;

  procedure AppendCp(var ADst: TCodePointArray; ACh: Cardinal);
  begin
    SetLength(ADst, Length(ADst) + 1);
    ADst[High(ADst)] := ACh;
  end;

  procedure AppendRange(var ADst: TCodePointArray; const ASrc: TCodePointArray);
  var
    LOld: Integer;
  begin
    LOld := Length(ADst);
    SetLength(ADst, LOld + Length(ASrc));
    if Length(ASrc) > 0 then
      Move(ASrc[0], ADst[LOld], Length(ASrc) * SizeOf(Cardinal));
  end;

var
  LWords: array of TCodePointArray;
  LWordCount, LLineCount, LLen, I: Integer;
  LWord, LRest, LLine, LCand: TCodePointArray;
begin
  Result := nil;
  LWords := nil;

  // split into words on spaces (word = maximal run of non-space code points)
  LWordCount := 0;
  I := 0;
  while I < Length(ACodePoints) do
  begin
    if ACodePoints[I] = $20 then
    begin
      Inc(I);
      Continue;
    end;
    LLen := 0;
    while (I + LLen < Length(ACodePoints)) and (ACodePoints[I + LLen] <> $20) do
      Inc(LLen);
    Inc(LWordCount);
    SetLength(LWords, LWordCount);
    LWords[LWordCount - 1] := Copy(ACodePoints, I, LLen);
    Inc(I, LLen);
  end;
  if LWordCount = 0 then
    Exit;

  // greedy wrap on pixel widths; the last allowed line is finished off
  // with an ellipsis
  LLineCount := 0;
  LLine := nil;
  I := 0;
  while I < LWordCount do
  begin
    LWord := LWords[I];
    LCand := nil;
    AppendRange(LCand, LLine);
    if Length(LLine) > 0 then
      AppendCp(LCand, $20);
    AppendRange(LCand, LWord);
    if CaptionLineWidthPix(ACanvas, LCand, APx) <= AMaxWidthPx then
    begin
      LLine := LCand;
      Inc(I);
      Continue;
    end;
    if Length(LLine) > 0 then
    begin
      // this line would fill the last available slot: ellipsize it
      if LLineCount = AMaxLines - 1 then
      begin
        EllipsizeLine(LLine, ACanvas, AMaxWidthPx, APx);
        SetLength(Result, LLineCount + 1);
        Result[LLineCount] := LLine;
        Exit;
      end;
      SetLength(Result, LLineCount + 1);
      Result[LLineCount] := LLine;
      Inc(LLineCount);
      LLine := nil;
      Continue;
    end;
    // a single word longer than a whole line: break it by characters
    if LLineCount = AMaxLines - 1 then
    begin
      LLine := Copy(LWord, 0, Length(LWord));
      EllipsizeLine(LLine, ACanvas, AMaxWidthPx, APx);
      SetLength(Result, LLineCount + 1);
      Result[LLineCount] := LLine;
      Exit;
    end;
    // find the largest prefix of the word that fits a whole line
    LLen := Length(LWord);
    while LLen > 1 do
    begin
      LCand := Copy(LWord, 0, LLen);
      if CaptionLineWidthPix(ACanvas, LCand, APx) <= AMaxWidthPx then
        Break;
      Dec(LLen);
    end;
    SetLength(Result, LLineCount + 1);
    Result[LLineCount] := Copy(LWord, 0, LLen);
    Inc(LLineCount);
    // the remainder of the word is reprocessed on the next iteration
    LRest := Copy(LWord, LLen, Length(LWord) - LLen);
    LWords[I] := LRest;
  end;
  if Length(LLine) > 0 then
  begin
    SetLength(Result, LLineCount + 1);
    Result[LLineCount] := LLine;
  end;
end;

procedure TForm1.BuildCaptionLines(ACanvas: TCanvas; ALines: TStrings;
  AMaxWidthPx, APx, AMaxLines: Integer; out AResult: TCaptionLines);
var
  I, J, LFirst, LLast: Integer;
  LCp: TCodePointArray;
  LPart: TCaptionLines;
begin
  AResult := nil;

  // skip empty lines at both ends of the text
  LFirst := 0;
  LLast := ALines.Count - 1;
  while (LFirst <= LLast) and (Trim(ALines[LFirst]) = '') do
    Inc(LFirst);
  while (LLast >= LFirst) and (Trim(ALines[LLast]) = '') do
    Dec(LLast);

  for I := LFirst to LLast do
  begin
    if Length(AResult) = AMaxLines then
    begin
      // more source lines than the caption can hold: mark the cut
      EllipsizeLine(AResult[High(AResult)], ACanvas, AMaxWidthPx, APx);
      Break;
    end;
    LCp := Utf8ToCodePoints(Trim(ALines[I]));
    if Length(LCp) = 0 then
    begin
      // explicit blank line inside the text: keep it as a spacer
      SetLength(AResult, Length(AResult) + 1);
      Continue;
    end;
    LPart := WrapCaptionLine(ACanvas, LCp, AMaxWidthPx, APx,
      AMaxLines - Length(AResult));
    for J := 0 to High(LPart) do
    begin
      SetLength(AResult, Length(AResult) + 1);
      AResult[High(AResult)] := LPart[J];
    end;
  end;
end;

procedure TForm1.DrawCaptionLine(ACanvas: TCanvas;
  const ALine: TCodePointArray; AX, AY, APx: Integer);
var
  I, J, K, LRunStart, LX, LIdx: Integer;
  LKnown: Boolean;
  LText: String;
begin
  LX := AX;
  I := 0;
  while I < Length(ALine) do
  begin
    LKnown := CaptionGlyphIndex(ALine[I]) >= 0;
    LRunStart := I;
    while (I < Length(ALine)) and
          ((CaptionGlyphIndex(ALine[I]) >= 0) = LKnown) do
      Inc(I);
    if LKnown then
    begin
      // embedded pixel glyphs
      for LIdx := LRunStart to I - 1 do
      begin
        for J := 0 to CAPTION_GLYPH_ROWS - 1 do
          for K := 0 to CAPTION_GLYPH_COLS - 1 do
            if (CaptionGlyphs[CaptionGlyphIndex(ALine[LIdx])][J] and
                (1 shl K)) <> 0 then
              ACanvas.FillRect(LX + K * APx, AY + J * APx,
                LX + (K + 1) * APx, AY + (J + 1) * APx);
        Inc(LX, CAPTION_GLYPH_ADVANCE * APx);
      end;
    end
    else
    begin
      // TrueType fallback: the system font renders the glyphs the pixel
      // font does not have (font linking / Pango covers CJK and friends)
      LText := '';
      for LIdx := LRunStart to I - 1 do
        LText := LText + CaptionCodePointToUtf8(ALine[LIdx]);
      ACanvas.Brush.Style := bsClear;
      ACanvas.TextOut(LX, AY, LText);
      Inc(LX, ACanvas.TextWidth(LText) + APx);
      ACanvas.Brush.Style := bsSolid;
    end;
  end;
end;

procedure TForm1.ComposeCaption(ASource, ADest: TBitmap);
const
  cCaptionMaxLines = 3;
var
  LSrcLines: TStringList;
  LFontPx, LFontH, LPad, LLineH, LBandH, LMaxTextW, I, LX, LY: Integer;
  LCaption: TCaptionLines;
begin
  LSrcLines := TStringList.Create;
  try
    // the memo text keeps the line breaks the user typed; the caption
    // shows them as real line breaks too
    LSrcLines.Text := memText.Text;

    // pixel size of the embedded font: grows with the scale, capped
    LFontPx := Max(1, Min(seScale.Value div 4, 5));
    LPad := Max(4, seScale.Value div 2);
    LMaxTextW := ASource.Width - 2 * LPad;
    if LMaxTextW < CAPTION_GLYPH_ADVANCE * LFontPx then
      LMaxTextW := CAPTION_GLYPH_ADVANCE * LFontPx;

    // TrueType fallback runs are measured and drawn at the caption line
    // height so their baselines stay close to the pixel glyphs
    LFontH := (CAPTION_GLYPH_ROWS + 1) * LFontPx;
    ASource.Canvas.Font.Height := -LFontH;

    BuildCaptionLines(ASource.Canvas, LSrcLines, LMaxTextW, LFontPx,
      cCaptionMaxLines, LCaption);
    if Length(LCaption) = 0 then
    begin
      ADest.Assign(ASource);
      Exit;
    end;

    LLineH := (CAPTION_GLYPH_ROWS + 1) * LFontPx;
    LBandH := 2 * LPad + Length(LCaption) * LLineH;

    ADest.SetSize(ASource.Width, ASource.Height + LBandH);
    ADest.Canvas.Brush.Color := cbLight.ButtonColor;
    ADest.Canvas.FillRect(0, 0, ADest.Width, ADest.Height);
    ADest.Canvas.Draw(0, 0, ASource);

    ADest.Canvas.Font.Height := -LFontH;
    ADest.Canvas.Font.Color := cbDark.ButtonColor;
    ADest.Canvas.Brush.Color := cbDark.ButtonColor;
    ADest.Canvas.Brush.Style := bsSolid;
    LY := ASource.Height + LPad;
    for I := 0 to High(LCaption) do
    begin
      LX := (ADest.Width -
        CaptionLineWidthPix(ASource.Canvas, LCaption[I], LFontPx)) div 2;
      DrawCaptionLine(ADest.Canvas, LCaption[I], LX, LY, LFontPx);
      Inc(LY, LLineH);
    end;
    ADest.Canvas.Brush.Style := bsClear;
  finally
    LSrcLines.Free;
  end;
end;

procedure TForm1.UpdateQrCode;
var
  LLightColor, LDarkColor: TColor;
  LQRCode: IQrCode;
  LBitmap: TQRCodeGenLibBitmap;
  LVersion, LCharCount, LTotalBits, I: Integer;
  LMode: String;
  LEccLevel: TQrCode.TEcc;
begin
  lblTextHint.Visible := (memText.Text = '');

  LLightColor := cbLight.ButtonColor;
  LDarkColor := cbDark.ButtonColor;

  FSegments := TQrSegment.MakeSegments(memText.Text, TEncoding.UTF8);

  try
    LQRCode := TQrCode.EncodeSegments(FSegments, SelectedEcc, seMinVer.Value,
      seMaxVer.Value, seMask.Value, chkBoost.Checked);
  except
    on E: EQRCodeGenLibException do
    begin
      ShowError(E.Message);
      Exit;
    end;
  end;

  FQRCode := LQRCode;
  LQRCode.BackgroundColor := LLightColor;
  LQRCode.ForegroundColor := LDarkColor;

  try
    LBitmap := LQRCode.ToBitmapImage(seScale.Value, seBorder.Value);
    try
      if chkCaption.Checked and (memText.Text <> '') then
        ComposeCaption(LBitmap, imgPreview.Picture.Bitmap)
      else
        imgPreview.Picture.Bitmap.Assign(LBitmap);
    finally
      LBitmap.Free;
    end;
  except
    on E: Exception do
    begin
      ShowError(E.Message);
      Exit;
    end;
  end;

  LVersion := LQRCode.Version;
  LCharCount := 0;
  for I := 0 to High(FSegments) do
    Inc(LCharCount, FSegments[I].NumChars);
  if Length(FSegments) > 0 then
    LMode := ModeName(FSegments[0].Mode)
  else
    LMode := 'none';
  LTotalBits := TQrSegment.GetTotalBits(FSegments, LVersion);
  if LTotalBits < 0 then
    LTotalBits := 0;
  if chkBoost.Checked then
    LEccLevel := BoostedEcc(LVersion)
  else
    LEccLevel := SelectedEcc;

  lblStatistics.Caption := Format(
    'QR Code version = %d, mask pattern = %d, character count = %d, ' +
    'encoding mode = %s, error correction = level %s, data bits = %d.',
    [LVersion, LQRCode.Mask, LCharCount, LMode, EccLetter(LEccLevel),
     LTotalBits]);
end;

procedure TForm1.DownloadClick(Sender: TObject);
var
  LPNG: TPortableNetworkGraphic;
  LExt: String;
begin
  if FQRCode = nil then
    Exit;
  with TSaveDialog.Create(Self) do
  try
    if rbVector.Checked then
    begin
      DefaultExt := 'svg';
      Filter := 'SVG image (*.svg)|*.svg';
    end
    else
    begin
      DefaultExt := 'png';
      Filter := 'PNG image (*.png)|*.png|Windows bitmap (*.bmp)|*.bmp';
    end;
    FileName := 'qr-code';
    Options := Options + [ofOverwritePrompt];
    if not Execute then
      Exit;
    LExt := LowerCase(ExtractFileExt(FileName));

    if rbVector.Checked then
    begin
      if not FQRCode.ToSvgFile(seBorder.Value, FileName) then
        MessageDlg('QR Code Generator', 'Failed to save the SVG file.',
          mtError, [mbOK], 0);
    end
    else if LExt = '.bmp' then
      imgPreview.Picture.Bitmap.SaveToFile(FileName)
    else
    begin
      LPNG := TPortableNetworkGraphic.Create;
      try
        LPNG.Assign(imgPreview.Picture.Bitmap);
        LPNG.SaveToFile(FileName);
      finally
        LPNG.Free;
      end;
    end;
  finally
    Free;
  end;
end;

procedure TForm1.ShowError(const AMessage: String);
begin
  FQRCode := nil;
  FSegments := nil;
  ClearPreview;
  lblStatistics.Caption := 'Error: ' + AMessage + '.';
end;

procedure TForm1.ClearPreview;
begin
  imgPreview.Picture.Bitmap.SetSize(0, 0);
end;

end.
