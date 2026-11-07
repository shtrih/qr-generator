unit ZXing.Helpers;

{
  * Copyright 2008 ZXing authors
  *
  * Licensed under the Apache License, Version 2.0 (the "License");
  * you may not use this file except in compliance with the License.
  * You may obtain a copy of the License at
  *
  *      http://www.apache.org/licenses/LICENSE-2.0
  *
  * Unless required by applicable law or agreed to in writing, software
  * distributed under the License is distributed on an "AS IS" BASIS,
  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  * See the License for the specific language governing permissions and
  * limitations under the License.

  * Implemented by E. Spelt for Delphi
}

{$IFDEF FPC}
  {$mode delphi}{$H+}
{$ENDIF}

interface

type
  TIntegerArray = TArray<Integer>;

  TArray = class
    class function Clone(original: TIntegerArray): TIntegerArray; static;
    class function CopyInSameArray(const Input: TIntegerArray;
      StartIndex: Integer; Len: Integer): TIntegerArray; static;
    class procedure Copy(const Source: TIntegerArray; var Target: TIntegerArray; SI, DI, Cnt: integer); static;
  end;

implementation

class function TArray.Clone(original: TIntegerArray): TIntegerArray;
var
  i: Integer;
  l: SmallInt;
begin
  l := Length(original);
  Result := TIntegerArray.Create{$ifndef FPC}(){$endif};
  SetLength(Result, l);

  for i := 0 to l - 1 do
  begin
    Result[i] := original[i];
  end;
end;

class function TArray.CopyInSameArray(const Input: TIntegerArray;
  StartIndex: Integer; Len: Integer): TIntegerArray;
var
  i, y: Integer;
begin
  Result := TArray.Clone(Input);

  y := 0;
  for i := StartIndex to (StartIndex + Len -1) do
  begin
    Result[y] := Input[i];
    inc(y);
  end;

end;

class procedure TArray.Copy(const Source: TIntegerArray; var Target: TIntegerArray; SI, DI, Cnt: integer);
begin
  System.Move(Pointer(@Source[SI])^, Pointer(@Target[DI])^, Cnt * SizeOf(Integer));
end;

end.
