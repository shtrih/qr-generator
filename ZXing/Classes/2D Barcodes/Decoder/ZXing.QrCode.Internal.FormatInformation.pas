{
  * Copyright 2007 ZXing authors
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

  * Original Author: Sean Owen
  * Ported from ZXING Java Source: www.Redivivus.in (suraj.supekar@redivivus.in)
  * Delphi Implementation by E. Spelt and K. Gossens
}

unit ZXing.QrCode.Internal.FormatInformation;

{$IFDEF FPC}
  {$mode delphi}{$H+}
{$ENDIF}

interface

uses
  Classes,
  Generics.Collections,
  ZXing.QrCode.Internal.ErrorCorrectionLevel,
  ZXing.Common.Detector.MathUtils;

type
  TIntegerArray=TArray<Integer>;
  {$ifndef FPC}
  PtrInt = integer;
  {$endif}


  IFormatInformation = interface
    function GetDataMask:Byte;
    function GetErrorCorrectionLevel: TErrorCorrectionLevel;
    function Equals(o: TObject): Boolean;
     function GetHashCode: PtrInt;
    property ErrorCorrectionLevel: TErrorCorrectionLevel read GetErrorCorrectionLevel;
    property DataMask: Byte read GetDataMask;
  end;


  /// <summary> <p>Encapsulates a QR Code's format information, including the data mask used and
  /// error correction level.</p>
  ///
  /// </summary>
  /// <seealso cref="TDataMask">
  /// </seealso>
  /// <seealso cref="TErrorCorrectionLevel">
  /// </seealso>
  TFormatInformation = class sealed (TInterfacedObject, IFormatInformation)
  private
    FErrorCorrectionLevel: TErrorCorrectionLevel;
    FDataMask: Byte;
    function GetDataMask:Byte;
    function GetErrorCorrectionLevel: TErrorCorrectionLevel;
  public
    constructor Create(const formatInfo: Integer);
    function Equals(o: TObject): Boolean; override;
    function GetHashCode: PtrInt; override;
    property ErrorCorrectionLevel: TErrorCorrectionLevel
      read FErrorCorrectionLevel;
    property DataMask: Byte read FDataMask;
  end;

  function numBitsDiffering(a, b: Integer): Integer;
  function DecodeFormatInformation(const maskedFormatInfo1, maskedFormatInfo2: Integer):IFormatInformation;

implementation

const
  FORMAT_INFO_MASK_QR: Integer = $5412;

var
  /// <summary> See ISO 18004:2006, Annex C, Table C.1</summary>
  FORMAT_INFO_DECODE_LOOKUP: TArray<TIntegerArray>;

    /// <summary> Offset i holds the number of 1 bits in the binary representation of i</summary>
  BITS_SET_IN_HALF_BYTE: TIntegerArray;

{ TFormatInformation }

constructor TFormatInformation.Create(const formatInfo: Integer);
begin
  // Bits 3,4
  FErrorCorrectionLevel := TErrorCorrectionLevel.forBits
    (TMathUtils.Asr(formatInfo, 3) and $03);
  // Bottom 3 bits
  FDataMask := Byte(formatInfo and 7);
end;

function TFormatInformation.Equals(o: TObject): Boolean;
var
  other: TFormatInformation;
begin
  Result := false;
  if (not(o is TFormatInformation)) then
    exit;

  other := TFormatInformation(o);
  Result := ((FErrorCorrectionLevel = other.ErrorCorrectionLevel) and
    (FDataMask = other.DataMask));
end;

function TFormatInformation.GetHashCode: PtrInt;
begin
  Result := ((FErrorCorrectionLevel.ordinal shl 3) or FDataMask)
end;

function TFormatInformation.GetDataMask:Byte;
begin
  result:=FDataMask;
end;

function TFormatInformation.GetErrorCorrectionLevel: TErrorCorrectionLevel;
begin
  result:=FErrorCorrectionLevel;
end;

function numBitsDiffering(a, b: Integer): Integer;
begin
  a := (a xor b); // a now has a 1 bit exactly where its bit differs with b's
  // Count bits set quickly with a series of lookups:
  Result := BITS_SET_IN_HALF_BYTE[(a and $0F)] + BITS_SET_IN_HALF_BYTE
    [TMathUtils.Asr(UInt32(a), 4) and $0F] + BITS_SET_IN_HALF_BYTE
    [TMathUtils.Asr(UInt32(a), 8) and $0F] + BITS_SET_IN_HALF_BYTE
    [TMathUtils.Asr(UInt32(a), 12) and $0F] + BITS_SET_IN_HALF_BYTE
    [TMathUtils.Asr(UInt32(a), 16) and $0F] + BITS_SET_IN_HALF_BYTE
    [TMathUtils.Asr(UInt32(a), 20) and $0F] + BITS_SET_IN_HALF_BYTE
    [TMathUtils.Asr(UInt32(a), 24) and $0F] + BITS_SET_IN_HALF_BYTE
    [TMathUtils.Asr(UInt32(a), 28) and $0F];
end;

function decodeFormatInformation(const maskedFormatInfo1, maskedFormatInfo2: Integer): IFormatInformation;
var
  formatInfo: IFormatInformation;
  function doDecodeFormatInformation(const maskedFormatInfo1, maskedFormatInfo2: Integer): IFormatInformation;
  var
    bestDifference, bestFormatInfo, bitsDifference, targetInfo: Integer;
    decodeInfo: TIntegerArray;
  begin
    Result := nil;

    // Find the int in FORMAT_INFO_DECODE_LOOKUP with fewest bits differing
    bestDifference := High(Integer);
    bestFormatInfo := 0;

    for decodeInfo in FORMAT_INFO_DECODE_LOOKUP do
    begin
      targetInfo := decodeInfo[0];
      if ((targetInfo = maskedFormatInfo1) or (targetInfo = maskedFormatInfo2))
      then
      begin
        // Found an exact match
        Result := TFormatInformation.Create(decodeInfo[1]);
        exit;
      end;

      bitsDifference := numBitsDiffering(maskedFormatInfo1, targetInfo);
      if (bitsDifference < bestDifference) then
      begin
        bestFormatInfo := decodeInfo[1];
        bestDifference := bitsDifference;
      end;

      if (maskedFormatInfo1 <> maskedFormatInfo2) then
      begin
        // also try the other option
        bitsDifference := numBitsDiffering(maskedFormatInfo2, targetInfo);
        if (bitsDifference < bestDifference) then
        begin
          bestFormatInfo := decodeInfo[1];
          bestDifference := bitsDifference;
        end;
      end;
    end;
    // Hamming distance of the 32 masked codes is 7, by construction, so <= 3 bits
    // differing means we found a match
    if (bestDifference <= 3) then
    begin
      Result := TFormatInformation.Create(bestFormatInfo);
      exit;
    end;
  end;
begin
  formatInfo := doDecodeFormatInformation(maskedFormatInfo1, maskedFormatInfo2);

  if (formatInfo <> nil) then
    Result := formatInfo
  else
    // Should return null, but, some QR codes apparently
    // do not mask this info. Try again by actually masking the pattern
    // first
    Result := doDecodeFormatInformation
      ((maskedFormatInfo1 xor FORMAT_INFO_MASK_QR),
      (maskedFormatInfo2 xor FORMAT_INFO_MASK_QR));
end;

procedure InitializeClass;
begin
  SetLength(FORMAT_INFO_DECODE_LOOKUP, $20);

  FORMAT_INFO_DECODE_LOOKUP[0] := TIntegerArray.Create($5412, 0);
  FORMAT_INFO_DECODE_LOOKUP[1] := TIntegerArray.Create($5125, 1);
  FORMAT_INFO_DECODE_LOOKUP[2] := TIntegerArray.Create($5E7C, 2);
  FORMAT_INFO_DECODE_LOOKUP[3] := TIntegerArray.Create($5B4B, 3);
  FORMAT_INFO_DECODE_LOOKUP[4] := TIntegerArray.Create($45F9, 4);
  FORMAT_INFO_DECODE_LOOKUP[5] := TIntegerArray.Create($40CE, 5);
  FORMAT_INFO_DECODE_LOOKUP[6] := TIntegerArray.Create($4F97, 6);
  FORMAT_INFO_DECODE_LOOKUP[7] := TIntegerArray.Create($4AA0, 7);
  FORMAT_INFO_DECODE_LOOKUP[8] := TIntegerArray.Create($77C4, 8);
  FORMAT_INFO_DECODE_LOOKUP[9] := TIntegerArray.Create($72F3, 9);
  FORMAT_INFO_DECODE_LOOKUP[10] := TIntegerArray.Create($7DAA, 10);
  FORMAT_INFO_DECODE_LOOKUP[11] := TIntegerArray.Create($789D, 11);
  FORMAT_INFO_DECODE_LOOKUP[12] := TIntegerArray.Create($662F, 12);
  FORMAT_INFO_DECODE_LOOKUP[13] := TIntegerArray.Create($6318, 13);
  FORMAT_INFO_DECODE_LOOKUP[14] := TIntegerArray.Create($6C41, 14);
  FORMAT_INFO_DECODE_LOOKUP[15] := TIntegerArray.Create($6976, 15);
  FORMAT_INFO_DECODE_LOOKUP[$10] := TIntegerArray.Create($1689, $10);
  FORMAT_INFO_DECODE_LOOKUP[$11] := TIntegerArray.Create($13BE, $11);
  FORMAT_INFO_DECODE_LOOKUP[$12] := TIntegerArray.Create($1CE7, $12);
  FORMAT_INFO_DECODE_LOOKUP[$13] := TIntegerArray.Create($19D0, $13);
  FORMAT_INFO_DECODE_LOOKUP[20] := TIntegerArray.Create($762, 20);
  FORMAT_INFO_DECODE_LOOKUP[$15] := TIntegerArray.Create($255, $15);
  FORMAT_INFO_DECODE_LOOKUP[$16] := TIntegerArray.Create($D0C, $16);
  FORMAT_INFO_DECODE_LOOKUP[$17] := TIntegerArray.Create($83B, $17);
  FORMAT_INFO_DECODE_LOOKUP[$18] := TIntegerArray.Create($355F, $18);
  FORMAT_INFO_DECODE_LOOKUP[$19] := TIntegerArray.Create($3068, $19);
  FORMAT_INFO_DECODE_LOOKUP[$1A] := TIntegerArray.Create($3F31, $1A);
  FORMAT_INFO_DECODE_LOOKUP[$1B] := TIntegerArray.Create($3A06, $1B);
  FORMAT_INFO_DECODE_LOOKUP[$1C] := TIntegerArray.Create($24B4, $1C);
  FORMAT_INFO_DECODE_LOOKUP[$1D] := TIntegerArray.Create($2183, $1D);
  FORMAT_INFO_DECODE_LOOKUP[30] := TIntegerArray.Create($2EDA, 30);
  FORMAT_INFO_DECODE_LOOKUP[$1F] := TIntegerArray.Create($2BED, $1F);

  BITS_SET_IN_HALF_BYTE := TIntegerArray.Create(0, 1, 1, 2, 1, 2, 2, 3, 1, 2,
    2, 3, 2, 3, 3, 4);
end;

procedure FinalizeClass;
var
  i: Integer;
begin
  for i := 0 to Pred(Length(FORMAT_INFO_DECODE_LOOKUP)) do
    FORMAT_INFO_DECODE_LOOKUP[i] := nil;

  FORMAT_INFO_DECODE_LOOKUP := nil;
  BITS_SET_IN_HALF_BYTE := nil;
end;

initialization
  InitializeClass;

finalization
  FinalizeClass;

end.
