unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Spin, Math, QlpIQrCode, QlpIQrSegment, QlpQrCode, QlpQrSegment,
  QlpQrSegmentMode, QlpQRCodeGenLibTypes;

type

  { Caption line list returned by TForm1.WrapCaptionLines }

  TCaptionLines = array of String;

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
    function WrapCaptionLines(ACanvas: TCanvas; const AText: String;
      AMaxWidth, AMaxLines: Integer): TCaptionLines;
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

function TForm1.WrapCaptionLines(ACanvas: TCanvas; const AText: String;
  AMaxWidth, AMaxLines: Integer): TCaptionLines;

  // removes the last UTF-8 character (dropping the last byte alone could
  // cut a multi-byte sequence in half and leave an invalid string)
  procedure DeleteLastChar(var S: String);
  begin
    if S = '' then
      Exit;
    Delete(S, Length(S), 1);
    while (S <> '') and ((Byte(S[Length(S)]) and $C0) = $80) do
      Delete(S, Length(S), 1);
  end;

var
  LWords: TCaptionLines;
  LWordCount, I: Integer;
  LWord, LLine, LTest: String;
begin
  Result := nil;
  LWords := nil;

  // split the (already flattened) text into space-separated words
  LWordCount := 0;
  LWord := '';
  for I := 1 to Length(AText) do
    if AText[I] <> ' ' then
      LWord := LWord + AText[I]
    else if LWord <> '' then
    begin
      Inc(LWordCount);
      SetLength(LWords, LWordCount);
      LWords[LWordCount - 1] := LWord;
      LWord := '';
    end;
  if LWord <> '' then
  begin
    Inc(LWordCount);
    SetLength(LWords, LWordCount);
    LWords[LWordCount - 1] := LWord;
  end;
  if LWordCount = 0 then
    Exit;

  // greedy wrap; the last allowed line is finished off with an ellipsis
  LLine := '';
  I := 0;
  while I < LWordCount do
  begin
    if LLine = '' then
      LTest := LWords[I]
    else
      LTest := LLine + ' ' + LWords[I];
    if ACanvas.TextWidth(LTest) <= AMaxWidth then
    begin
      LLine := LTest;
      Inc(I);
      Continue;
    end;
    if LLine <> '' then
    begin
      // flushing would consume the last available line: ellipsize it
      if Length(Result) = AMaxLines - 1 then
      begin
        while (LLine <> '') and
          (ACanvas.TextWidth(LLine + '…') > AMaxWidth) do
          DeleteLastChar(LLine);
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := LLine + '…';
        Exit;
      end;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LLine;
      LLine := '';
      Continue;
    end;
    // a single word wider than a whole line: break it by characters
    if Length(Result) = AMaxLines - 1 then
    begin
      while (LWords[I] <> '') and
        (ACanvas.TextWidth(LWords[I] + '…') > AMaxWidth) do
        DeleteLastChar(LWords[I]);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LWords[I] + '…';
      Exit;
    end;
    LWord := LWords[I];
    while (LWord <> '') and (ACanvas.TextWidth(LWord) > AMaxWidth) do
      DeleteLastChar(LWord);
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LWord;
    LWords[I] := Copy(LWords[I], Length(LWord) + 1, MaxInt);
    // the remainder of the word is reprocessed on the next iteration
  end;
  if LLine <> '' then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LLine;
  end;
end;

procedure TForm1.ComposeCaption(ASource, ADest: TBitmap);
const
  // caption font height in bitmap pixels: grows with the scale, capped
  cCaptionFontMinPx = 8;
  cCaptionFontMaxPx = 48;
  cCaptionMaxLines = 3;
var
  LFontH, LPad, LLineH, LBandH, LMaxTextW, I, LY: Integer;
  LText: String;
  LLines: TCaptionLines;
begin
  // flatten the encoded text into a single line for the caption
  LText := StringReplace(memText.Text, #13#10, ' ', [rfReplaceAll]);
  LText := StringReplace(LText, #10, ' ', [rfReplaceAll]);
  LText := StringReplace(LText, #13, ' ', [rfReplaceAll]);
  LText := Trim(LText);

  LFontH := Min(Max(seScale.Value * 2, cCaptionFontMinPx), cCaptionFontMaxPx);
  LPad := Max(4, seScale.Value div 2);
  LMaxTextW := ASource.Width - 2 * LPad;
  if LMaxTextW < 8 then
    LMaxTextW := 8;

  ASource.Canvas.Font.Height := -LFontH;
  LLines := WrapCaptionLines(ASource.Canvas, LText, LMaxTextW,
    cCaptionMaxLines);
  if Length(LLines) = 0 then
  begin
    ADest.Assign(ASource);
    Exit;
  end;

  LLineH := LFontH * 5 div 4;
  LBandH := 2 * LPad + Length(LLines) * LLineH;

  ADest.SetSize(ASource.Width, ASource.Height + LBandH);
  ADest.Canvas.Brush.Color := cbLight.ButtonColor;
  ADest.Canvas.FillRect(0, 0, ADest.Width, ADest.Height);
  ADest.Canvas.Draw(0, 0, ASource);

  ADest.Canvas.Font.Height := -LFontH;
  ADest.Canvas.Font.Color := cbDark.ButtonColor;
  ADest.Canvas.Brush.Style := bsClear;
  LY := ASource.Height + LPad + (LLineH - LFontH) div 2;
  for I := 0 to High(LLines) do
  begin
    ADest.Canvas.TextOut(
      (ADest.Width - ADest.Canvas.TextWidth(LLines[I])) div 2, LY, LLines[I]);
    Inc(LY, LLineH);
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
