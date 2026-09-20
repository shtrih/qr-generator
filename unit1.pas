unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Spin, QlpIQrCode, QlpIQrSegment, QlpQrCode, QlpQrSegment, QlpQrSegmentMode,
  QlpQRCodeGenLibTypes;

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
