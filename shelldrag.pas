{
  OLE drag & drop of a file out to other applications (Windows Explorer etc.).

  DragFileToShell starts a blocking drag loop offering a single CF_HDROP
  format that points at an existing file; the drop target (for example
  Explorer) copies the file itself, so the caller may delete the file as
  soon as the call returns. Returns the final DROPEFFECT_* value, 0 when
  nothing was dropped or when the platform has no drag-out support.

  All file names handled here are UTF-8 strings without relying on their
  declared code page (the LCL convention): the conversions are done
  byte-wise with LazUTF8, never through UnicodeString casts.

  OLE is already initialized for LCL applications on Windows
  (OleInitialize in TWin32WidgetSet.AppInit), so nothing is initialized here.
}

unit ShellDrag;

{$mode objfpc}{$H+}

interface

{ Returns the system temporary directory with a trailing path delimiter,
  as a UTF-8 string; '' when it cannot be determined. }
function ShellTempDir: String;

function DragFileToShell(const AFileName: String): LongWord;

implementation

{$IFDEF WINDOWS}
uses
  SysUtils, Windows, ActiveX, ShlObj, LazUTF8;

type
  { IEnumFORMATETC over a fixed list of formats. }
  TFormatEtcList = class(TInterfacedObject, IEnumFormatEtc)
  private
    FFormats: array of FORMATETC;
    FIndex: Integer;
  public
    constructor Create(const AFormats: array of FORMATETC; AIndex: Integer = 0);
    function Next(celt: ULong; out rgelt: FORMATETC;
      pceltFetched: PULong): HResult; stdcall;
    function Skip(celt: ULong): HResult; stdcall;
    function Reset: HResult; stdcall;
    function Clone(out penum: IEnumFormatEtc): HResult; stdcall;
  end;

  { IDataObject exposing a single CF_HDROP format backed by a global block
    with a DROPFILES header and the wide file name. }
  TFileDropDataObject = class(TInterfacedObject, IDataObject)
  private
    FFormat: FORMATETC;
    FHGlobal: HGLOBAL;
    function CopyHGlobal(ASource: HGLOBAL): HGLOBAL;
  public
    constructor Create(const AFileName: String);
    destructor Destroy; override;
    function GetData(const formatetcIn: FORMATETC;
      out medium: STGMEDIUM): HResult; stdcall;
    function GetDataHere(const pformatetc: FORMATETC;
      out medium: STGMEDIUM): HResult; stdcall;
    function QueryGetData(const pformatetc: FORMATETC): HResult; stdcall;
    function GetCanonicalFormatEtc(const pformatetcIn: FORMATETC;
      out pformatetcOut: FORMATETC): HResult; stdcall;
    function SetData(const pformatetc: FORMATETC; var medium: STGMEDIUM;
      fRelease: BOOL): HResult; stdcall;
    function EnumFormatEtc(dwDirection: DWORD;
      out enumformatetcpara: IEnumFormatEtc): HResult; stdcall;
    function DAdvise(const formatetc: FORMATETC; advf: DWORD;
      const AdvSink: IAdviseSink; out dwConnection: DWORD): HResult; stdcall;
    function DUnadvise(dwConnection: DWORD): HResult; stdcall;
    function EnumDAdvise(out enumAdvise: IEnumStatData): HResult; stdcall;
  end;

  { IDropSource with the standard Esc / button-release handling. }
  TFileDropSource = class(TInterfacedObject, IDropSource)
  public
    function QueryContinueDrag(fEscapePressed: BOOL;
      grfKeyState: DWORD): HResult; stdcall;
    function GiveFeedback(dwEffect: DWORD): HResult; stdcall;
  end;

constructor TFormatEtcList.Create(const AFormats: array of FORMATETC;
  AIndex: Integer);
var
  I: Integer;
begin
  inherited Create;
  SetLength(FFormats, Length(AFormats));
  for I := 0 to High(AFormats) do
    FFormats[I] := AFormats[I];
  FIndex := AIndex;
end;

function TFormatEtcList.Next(celt: ULong; out rgelt: FORMATETC;
  pceltFetched: PULong): HResult; stdcall;
var
  LFetched: ULong;
  LTarget: PFormatEtc;
begin
  LFetched := 0;
  while (LFetched < celt) and (FIndex < Length(FFormats)) do
  begin
    LTarget := @rgelt;
    Inc(LTarget, LFetched);
    LTarget^ := FFormats[FIndex];
    Inc(FIndex);
    Inc(LFetched);
  end;
  if pceltFetched <> nil then
    pceltFetched^ := LFetched;
  if LFetched = celt then
    Result := S_OK
  else
    Result := S_FALSE;
end;

function TFormatEtcList.Skip(celt: ULong): HResult; stdcall;
begin
  Inc(FIndex, Integer(celt));
  if FIndex > Length(FFormats) then
    FIndex := Length(FFormats);
  if FIndex < Length(FFormats) then
    Result := S_OK
  else
    Result := S_FALSE;
end;

function TFormatEtcList.Reset: HResult; stdcall;
begin
  FIndex := 0;
  Result := S_OK;
end;

function TFormatEtcList.Clone(out penum: IEnumFormatEtc): HResult; stdcall;
begin
  penum := TFormatEtcList.Create(FFormats, FIndex);
  Result := S_OK;
end;

constructor TFileDropDataObject.Create(const AFileName: String);
var
  LName: UnicodeString;
  LDrop: PDROPFILES;
  LTarget: PWideChar;
begin
  inherited Create;
  FFormat.cfFormat := CF_HDROP;
  FFormat.ptd := nil;
  FFormat.dwAspect := DVASPECT_CONTENT;
  FFormat.lindex := -1;
  FFormat.tymed := TYMED_HGLOBAL;
  FHGlobal := 0;

  // the global block holds a DROPFILES header followed by the wide file
  // name and a double NUL terminator (the memory is zero-initialized)
  LName := UTF8ToUTF16(AFileName);
  FHGlobal := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT,
    SizeOf(TDROPFILES) + (Length(LName) + 2) * SizeOf(WideChar));
  if FHGlobal = 0 then
    raise EOSError.Create('Failed to allocate memory for the drag file list.');
  LDrop := PDROPFILES(GlobalLock(FHGlobal));
  if LDrop = nil then
  begin
    GlobalFree(FHGlobal);
    FHGlobal := 0;
    raise EOSError.Create('Failed to lock the drag file list memory.');
  end;
  try
    LDrop^.pFiles := SizeOf(TDROPFILES);
    LDrop^.fWide := True;
    if Length(LName) > 0 then
    begin
      LTarget := PWideChar(PByte(LDrop) + SizeOf(TDROPFILES));
      Move(LName[1], LTarget^, Length(LName) * SizeOf(WideChar));
    end;
  finally
    GlobalUnlock(FHGlobal);
  end;
end;

destructor TFileDropDataObject.Destroy;
begin
  if FHGlobal <> 0 then
    GlobalFree(FHGlobal);
  inherited Destroy;
end;

function TFileDropDataObject.CopyHGlobal(ASource: HGLOBAL): HGLOBAL;
var
  LSize: PTRUINT;
  LSource, LTarget: LPVOID;
begin
  Result := 0;
  LSize := GlobalSize(ASource);
  if (ASource = 0) or (LSize = 0) then
    Exit;
  Result := GlobalAlloc(GMEM_MOVEABLE, LSize);
  if Result = 0 then
    Exit;
  LSource := GlobalLock(ASource);
  LTarget := GlobalLock(Result);
  if (LSource <> nil) and (LTarget <> nil) then
    Move(LSource^, LTarget^, LSize);
  GlobalUnlock(ASource);
  GlobalUnlock(Result);
end;

function TFileDropDataObject.GetData(const formatetcIn: FORMATETC;
  out medium: STGMEDIUM): HResult; stdcall;
begin
  FillChar(medium, SizeOf(medium), 0);
  Result := QueryGetData(formatetcIn);
  if Result <> S_OK then
    Exit;
  medium.Tymed := TYMED_HGLOBAL;
  medium.hGlobal := CopyHGlobal(FHGlobal);
  if medium.hGlobal = 0 then
    Result := STG_E_MEDIUMFULL
  else
    Result := S_OK;
end;

function TFileDropDataObject.GetDataHere(const pformatetc: FORMATETC;
  out medium: STGMEDIUM): HResult; stdcall;
begin
  Result := E_NOTIMPL;
end;

function TFileDropDataObject.QueryGetData(
  const pformatetc: FORMATETC): HResult; stdcall;
begin
  if (pformatetc.cfFormat <> CF_HDROP) or
     (pformatetc.dwAspect <> DVASPECT_CONTENT) or
     (pformatetc.lindex <> -1) then
    Exit(DV_E_FORMATETC);
  if (pformatetc.tymed and TYMED_HGLOBAL) = 0 then
    Exit(DV_E_TYMED);
  Result := S_OK;
end;

function TFileDropDataObject.GetCanonicalFormatEtc(const pformatetcIn: FORMATETC;
  out pformatetcOut: FORMATETC): HResult; stdcall;
begin
  pformatetcOut := pformatetcIn;
  pformatetcOut.ptd := nil;
  Result := DATA_S_SAMEFORMATETC;
end;

function TFileDropDataObject.SetData(const pformatetc: FORMATETC;
  var medium: STGMEDIUM; fRelease: BOOL): HResult; stdcall;
begin
  Result := E_NOTIMPL;
end;

function TFileDropDataObject.EnumFormatEtc(dwDirection: DWORD;
  out enumformatetcpara: IEnumFormatEtc): HResult; stdcall;
begin
  if (dwDirection and (DATADIR_GET or DATADIR_SET)) = 0 then
    Exit(E_INVALIDARG);
  enumformatetcpara := TFormatEtcList.Create([FFormat]);
  Result := S_OK;
end;

function TFileDropDataObject.DAdvise(const formatetc: FORMATETC; advf: DWORD;
  const AdvSink: IAdviseSink; out dwConnection: DWORD): HResult; stdcall;
begin
  Result := E_NOTIMPL;
end;

function TFileDropDataObject.DUnadvise(dwConnection: DWORD): HResult; stdcall;
begin
  Result := E_NOTIMPL;
end;

function TFileDropDataObject.EnumDAdvise(
  out enumAdvise: IEnumStatData): HResult; stdcall;
begin
  Result := E_NOTIMPL;
end;

function TFileDropSource.QueryContinueDrag(fEscapePressed: BOOL;
  grfKeyState: DWORD): HResult; stdcall;
begin
  if fEscapePressed then
    Result := DRAGDROP_S_CANCEL
  else if (grfKeyState and MK_LBUTTON) = 0 then
    Result := DRAGDROP_S_DROP
  else
    Result := S_OK;
end;

function TFileDropSource.GiveFeedback(dwEffect: DWORD): HResult; stdcall;
begin
  Result := DRAGDROP_S_USEDEFAULTCURSORS;
end;

function ShellTempDir: String;
var
  LBuf: UnicodeString;
  LLen: DWORD;
  LTemp: RawByteString;
begin
  Result := '';
  LLen := GetTempPathW(0, nil);
  if LLen = 0 then
    Exit;
  SetLength(LBuf, LLen);
  LLen := GetTempPathW(LLen, PWideChar(LBuf));
  SetLength(LBuf, LLen);
  // relabel the UTF-8 bytes as code page 0 so that passing the string
  // around does not trigger any code page conversion
  LTemp := UTF16ToUTF8(LBuf);
  SetCodePage(LTemp, 0, False);
  Result := LTemp;
end;

function DragFileToShell(const AFileName: String): LongWord;
var
  LDataObject: IDataObject;
  LDropSource: IDropSource;
  LEffect: DWORD;
begin
  Result := 0;
  if AFileName = '' then
    Exit;
  LDataObject := TFileDropDataObject.Create(AFileName);
  LDropSource := TFileDropSource.Create;
  LEffect := DROPEFFECT_COPY;
  if DoDragDrop(LDataObject, LDropSource, DROPEFFECT_COPY, @LEffect) >= 0 then
    Result := LEffect;
end;

{$ELSE}

uses
  SysUtils;

function ShellTempDir: String;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir);
end;

function DragFileToShell(const AFileName: String): LongWord;
begin
  // drag-out to file managers is implemented for Windows only
  Result := 0;
end;

{$ENDIF}

end.
