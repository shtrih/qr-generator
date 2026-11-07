unit DecodeForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls;

type

  { TDecodeForm }

  TDecodeForm = class(TForm)
    btnClose: TButton;
    btnCopy: TButton;
    btnOpen: TButton;
    btnPaste: TButton;
    btnUse: TButton;
    dlgOpenImage: TOpenDialog;
    imgDecode: TImage;
    lblDecoded: TLabel;
    lblDecodeStatus: TLabel;
    lblFileName: TLabel;
    lblImage: TLabel;
    memDecoded: TMemo;
    procedure btnCopyClick(Sender: TObject);
    procedure btnOpenClick(Sender: TObject);
    procedure btnPasteClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
  private
    FDecodedText: String;
    function TryDecodeBitmap(ABitmap: TBitmap; out AText: String): Boolean;
    procedure LoadAndDecodePicture(APicture: TPicture; const ASourceName: String);
    procedure PasteFromClipboardImage;
    procedure ClearResult;
    procedure ShowStatus(const AMessage: String);
    procedure UpdateButtonState;
  public
    { Loads AFileName, shows it and decodes; call before ShowModal. }
    procedure LoadAndDecode(const AFileName: String);
    { The last successful decoding result (empty when nothing was decoded). }
    property DecodedText: String read FDecodedText;
  end;

implementation

{$R *.lfm}

uses
  Clipbrd, LCLType, CaptionFont, ZXing.ScanManager, ZXing.BarCodeFormat,
  ZXing.ReadResult;

{ TDecodeForm }

procedure TDecodeForm.FormCreate(Sender: TObject);
begin
  btnOpen.OnClick := @btnOpenClick;
  btnPaste.OnClick := @btnPasteClick;
  btnCopy.OnClick := @btnCopyClick;
  OnKeyDown := @FormKeyDown;
  OnDropFiles := @FormDropFiles;
  UpdateButtonState;
end;

procedure TDecodeForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = VK_V) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    PasteFromClipboardImage;
  end;
end;

procedure TDecodeForm.btnOpenClick(Sender: TObject);
begin
  if dlgOpenImage.Execute then
    LoadAndDecode(dlgOpenImage.FileName);
end;

procedure TDecodeForm.btnPasteClick(Sender: TObject);
begin
  PasteFromClipboardImage;
end;

procedure TDecodeForm.btnCopyClick(Sender: TObject);
begin
  Clipboard.AsText := memDecoded.Text;
end;

{ Decodes a QR code from a bitmap with the vendored ZXing port.
  Returns False when no QR code is found. }
function TDecodeForm.TryDecodeBitmap(ABitmap: TBitmap; out AText: String
  ): Boolean;
var
  Scan: TScanManager;
  Res: TReadResult;
  LDecoded: String;
begin
  Result := False;
  AText := '';
  if (ABitmap = nil) or ABitmap.Empty then
    Exit;
  Scan := TScanManager.Create(TBarcodeFormat.QR_CODE, nil);
  try
    try
      Res := Scan.Scan(ABitmap);
      if Res <> nil then
      begin
        LDecoded := Res.text;
        AText := LDecoded;
        Result := LDecoded <> '';
      end;
    except
      // Any decoding error is reported as "not found".
      Result := False;
    end;
  finally
    Scan.Free;
  end;
end;

procedure TDecodeForm.LoadAndDecodePicture(APicture: TPicture;
  const ASourceName: String);
var
  Bmp: TBitmap;
  LDecoded: String;
begin
  if (APicture.Graphic = nil) or APicture.Graphic.Empty then
  begin
    ClearResult;
    imgDecode.Picture.Bitmap.SetSize(0, 0);
    lblFileName.Caption := '';
    ShowStatus('No image to decode.');
    Exit;
  end;
  Bmp := TBitmap.Create;
  try
    // Normalize PNG/JPEG/etc. into a plain bitmap the reader accepts.
    Bmp.Assign(APicture.Graphic);
    imgDecode.Picture.Bitmap.Assign(Bmp);
    lblFileName.Caption := Format('%s  (%dx%d pixels)',
      [ASourceName, Bmp.Width, Bmp.Height]);
    if TryDecodeBitmap(Bmp, LDecoded) then
    begin
      FDecodedText := LDecoded;
      memDecoded.Text := LDecoded;
      ShowStatus(Format('Decoded %d characters.',
        [Length(Utf8ToCodePoints(LDecoded))]));
    end
    else
    begin
      ClearResult;
      ShowStatus('No QR code found in the image.');
    end;
    UpdateButtonState;
  finally
    Bmp.Free;
  end;
end;

procedure TDecodeForm.LoadAndDecode(const AFileName: String);
var
  Pic: TPicture;
begin
  Pic := TPicture.Create;
  try
    try
      Pic.LoadFromFile(AFileName);
    except
      on E: Exception do
      begin
        ClearResult;
        imgDecode.Picture.Bitmap.SetSize(0, 0);
        lblFileName.Caption := AFileName;
        ShowStatus('Could not load the image: ' + E.Message + '.');
        Exit;
      end;
    end;
    LoadAndDecodePicture(Pic, AFileName);
  finally
    Pic.Free;
  end;
end;

procedure TDecodeForm.PasteFromClipboardImage;
var
  Pic: TPicture;
begin
  if not Clipboard.HasFormat(CF_BITMAP) then
  begin
    ClearResult;
    ShowStatus('The clipboard does not contain an image.');
    Exit;
  end;
  Pic := TPicture.Create;
  try
    try
      Pic.Assign(Clipboard);
    except
      on E: Exception do
      begin
        ClearResult;
        ShowStatus('Could not load the image: ' + E.Message + '.');
        Exit;
      end;
    end;
    LoadAndDecodePicture(Pic, '(from clipboard)');
  finally
    Pic.Free;
  end;
end;

procedure TDecodeForm.ClearResult;
begin
  FDecodedText := '';
  memDecoded.Text := '';
end;

procedure TDecodeForm.ShowStatus(const AMessage: String);
begin
  lblDecodeStatus.Caption := AMessage;
end;

procedure TDecodeForm.UpdateButtonState;
begin
  btnCopy.Enabled := FDecodedText <> '';
  btnUse.Enabled := FDecodedText <> '';
end;

procedure TDecodeForm.FormDropFiles(Sender: TObject;
  const FileNames: array of string);
begin
  if Length(FileNames) > 0 then
    LoadAndDecode(FileNames[0]);
end;

end.
