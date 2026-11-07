unit ZXing.ByteSegments;

{$IFDEF FPC}
  {$mode delphi}{$H+}
{$ENDIF}

interface

type
    TByteArray = TArray<byte>;
    /// <summary>
    ///  implements the ByteSegments (which was declared as a TList<TArray<Byte>>
    ///  throughout the code as reference-counted interface object)
    /// </summary>
    IByteSegments = Interface
        ['{0994FC90-E8F5-40D8-8A48-9B05DFFF2635}']
        function Count:integer;
        procedure Clear;
        function GetCapacity: integer;
        procedure SetCapacity(const Value: integer);
        property Capacity:integer read GetCapacity write SetCapacity;
        function Add(const item:TByteArray):integer;
     end;


function ByteSegmentsCreate:IByteSegments;

implementation

uses
  SysUtils,
  Generics.Collections;

type
  TByteSegments = class(TInterfacedObject,IByteSegments)
  private
     FList: TList<TByteArray>;
     function Count:integer;
     procedure Clear;
     function GetCapacity: integer;
     procedure SetCapacity(const Value: integer);
     function Add(const item:TByteArray):integer;
  public
     constructor Create;
     destructor Destroy; override;
  end;


function ByteSegmentsCreate:IByteSegments;
begin
   result := TByteSegments.Create;

end;


{ TByteSegments }

function TByteSegments.Add(const item: TByteArray): integer;
begin
   result := FList.Add(item);
end;

procedure TByteSegments.Clear;
begin
   FList.Clear;
end;

function TByteSegments.Count: integer;
begin
   result := FList.Count;
end;

constructor TByteSegments.Create;
begin
   FList := TList<TByteArray>.Create;
   inherited Create;
end;

destructor TByteSegments.Destroy;
begin
  FList.Free;
  inherited;
end;

function TByteSegments.GetCapacity: integer;
begin
   result := FList.Capacity;
end;

procedure TByteSegments.SetCapacity(const Value: integer);
begin
  FList.Capacity := value;
end;

end.
