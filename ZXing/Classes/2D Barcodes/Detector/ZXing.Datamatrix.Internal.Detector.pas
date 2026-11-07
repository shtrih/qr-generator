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

  * Original Author: Sean Owen
  * Delphi Implementation by K. Gossens
}

unit ZXing.Datamatrix.Internal.Detector;

{$IFDEF FPC}
  {$mode delphi}{$H+}
{$ENDIF}

interface

uses
  SysUtils,
  Generics.Collections,
  Generics.Defaults,
  Math,
  ZXing.Common.BitMatrix,
  ZXing.DefaultGridSampler,
  ZXing.Common.DetectorResult,
  ZXing.ResultPoint,
  ZXing.Common.Detector.WhiteRectangleDetector;

type
  /// <summary>
  /// <p>Encapsulates logic that can detect a Data Matrix Code in an image, even if the Data Matrix Code
  /// is rotated or skewed, or partially obscured.</p>
  /// </summary>
  TDataMatrixDetector = class(TObject)
  private
    Fimage: TBitMatrix;
    FrectangleDetector: TWhiteRectangleDetector;
    function isValid(p: IResultPoint): Boolean;
    function correctTopRight(points:TIResultPointArray): IResultPoint;
    function shiftPoint(point,_to:IResultPoint;_div:integer):IResultPoint;
    function moveAway(point:IResultPoint;fromX,fromY:double):IResultPoint;
    function detectSolid1(cornerPoints:TIResultPointArray):TIResultPointArray;
    function detectSolid2(points:TIResultPointArray):TIResultPointArray;
    function shiftToModuleCenter(points:TIResultPointArray):TIResultPointArray;
    function transitionsBetween(Afrom, Ato: IResultPoint): integer;
    function sampleGrid(image: TBitMatrix; topLeft, bottomLeft, bottomRight,
      topRight: IResultPoint; dimensionX, dimensionY: Integer): TBitMatrix;
  public
    constructor Create(const image: TBitMatrix);
    destructor Destroy; override;
    function detect: TDetectorResult;
  end;

implementation

{ TDataMatrixDetector }

/// <summary>
/// Initializes a new instance of the <see cref="Detector"/> class.
/// </summary>
/// <param name="image">The image.</param>
constructor TDataMatrixDetector.Create(const image: TBitMatrix);
begin
  Self.Fimage := image;
  Self.FrectangleDetector := TWhiteRectangleDetector.New(image);
end;

destructor TDataMatrixDetector.Destroy;
begin
  if (FrectangleDetector <> nil) then
    FrectangleDetector.Free;
  inherited;
end;

/// <summary>
/// <p>Detects a Data Matrix Code in an image.</p>
/// </summary>
/// <returns><see cref="DetectorResult" />encapsulating results of detecting a Data Matrix Code or null</returns>
function TDataMatrixDetector.detect(): TDetectorResult;
var
  topRight,bottomLeft, bottomRight, topLeft: IResultPoint;
  cornerPoints: TIResultPointArray;
  points: TIResultPointArray;
  bits: TBitMatrix;
  corners: TIResultPointArray;
  dimensionTop, dimensionRight: Integer;
begin
  Result := nil;

  // can be null, if the image is to small
  if (FrectangleDetector = nil) then exit;

  try
    cornerPoints := FrectangleDetector.detect();
    if (cornerPoints = nil) then
      exit;

    points:= detectSolid1(cornerPoints);
    points:= detectSolid2(points);

    points[3]:=correctTopRight(points);
    if (points[3] = nil) then exit;

    points:=shiftToModuleCenter(points);

    topLeft := points[0];
    bottomLeft := points[1];
    bottomRight := points[2];
    topRight := points[3];

    dimensionTop := transitionsBetween(topLeft, topRight) + 1;
    dimensionRight := transitionsBetween(bottomRight, topRight) + 1;

    if ((dimensionTop AND $01) = 1) then Inc(dimensionTop);
    if ((dimensionRight AND $01) = 1) then Inc(dimensionRight);

    if ((4*dimensionTop < 7*dimensionRight) AND (4*dimensionRight < 7*dimensionTop)) then
    begin
      dimensionTop   := max(dimensionTop, dimensionRight);
      dimensionRight := dimensionTop;
    end;

    bits := sampleGrid(Fimage,
                       topLeft, bottomLeft, bottomRight,topRight,
                       dimensionTop, dimensionRight);

    corners := TIResultPointArray.Create(topLeft, bottomLeft, bottomRight, topRight);

    Result := TDetectorResult.Create(bits, corners);

  finally
    cornerPoints := nil;
  end;
end;

/// <summary>
/// Calculates the position of the white top right module using the output of the rectangle detector
/// for a square matrix
/// </summary>
function TDataMatrixDetector.correctTopRight(points:TIResultPointArray): IResultPoint;
var
  pointA, pointB, pointC, pointD : IResultPoint;
  pointAs, pointCs               : IResultPoint;
  candidate1, candidate2         : IResultPoint;
  trTop,trRight                  : integer;
  sumc1,sumc2                    : integer;
begin
  // A..D
  // |  :
  // B--C
  pointA := points[0];
  pointB := points[1];
  pointC := points[2];
  pointD := points[3];

  // shift points for safe transition detection.
  trTop := transitionsBetween(pointA, pointD);
  trRight := transitionsBetween(pointB, pointD);
  pointAs := shiftPoint(pointA, pointB, (trRight + 1) * 4);
  pointCs := shiftPoint(pointC, pointB, (trTop + 1) * 4);

  trTop := transitionsBetween(pointAs, pointD);
  trRight := transitionsBetween(pointCs, pointD);

  candidate1 := TResultPointHelpers.CreateResultPoint(
    pointD.X + (pointC.X - pointB.X) / (trTop + 1),
    pointD.Y + (pointC.Y - pointB.Y) / (trTop + 1));

  candidate2 := TResultPointHelpers.CreateResultPoint(
    pointD.X + (pointA.X - pointB.X) / (trRight + 1),
    pointD.Y + (pointA.Y - pointB.Y) / (trRight + 1));

  if (NOT isValid(candidate1)) then
  begin
    if (isValid(candidate2)) then
    begin
      result:=candidate2;
      exit
    end;
    result:=nil;
    exit;
  end;
  if (NOT isValid(candidate2)) then
  begin
    result:=candidate1;
    exit;
  end;

  sumc1 := transitionsBetween(pointAs, candidate1) + transitionsBetween(pointCs, candidate1);
  sumc2 := transitionsBetween(pointAs, candidate2) + transitionsBetween(pointCs, candidate2);

  if (sumc1 > sumc2) then
    result:=candidate1
  else
    result:=candidate2;

end;

function TDataMatrixDetector.shiftToModuleCenter(points:TIResultPointArray):TIResultPointArray;
var
  pointA, pointB, pointC, pointD     : IResultPoint;
  pointAs, pointBs, pointCs, pointDs : IResultPoint;
  dimH, dimV                         : integer;
  centerX, centerY                   : double;
begin
  // A..D
  // |  :
  // B--C
  pointA := points[0];
  pointB := points[1];
  pointC := points[2];
  pointD := points[3];

  // calculate pseudo dimensions
  dimH := transitionsBetween(pointA, pointD) + 1;
  dimV := transitionsBetween(pointC, pointD) + 1;

  // shift points for safe dimension detection
  pointAs := shiftPoint(pointA, pointB, dimV * 4);
  pointCs := shiftPoint(pointC, pointB, dimH * 4);

  //  calculate more precise dimensions
  dimH := transitionsBetween(pointAs, pointD) + 1;
  dimV := transitionsBetween(pointCs, pointD) + 1;
  if ((dimH AND $01) = 1) then
    Inc(dimH);
  if ((dimV AND $01) = 1) then
    Inc(dimV);

  // WhiteRectangleDetector returns points inside of the rectangle.
  // I want points on the edges.
  centerX := (pointA.X + pointB.X + pointC.X + pointD.X) / 4;
  centerY := (pointA.Y + pointB.Y + pointC.Y + pointD.Y) / 4;
  pointA := moveAway(pointA, centerX, centerY);
  pointB := moveAway(pointB, centerX, centerY);
  pointC := moveAway(pointC, centerX, centerY);
  pointD := moveAway(pointD, centerX, centerY);


  // shift points to the center of each modules
  pointAs := shiftPoint(pointA, pointB, dimV * 4);
  pointAs := shiftPoint(pointAs, pointD, dimH * 4);
  pointBs := shiftPoint(pointB, pointA, dimV * 4);
  pointBs := shiftPoint(pointBs, pointC, dimH * 4);
  pointCs := shiftPoint(pointC, pointD, dimV * 4);
  pointCs := shiftPoint(pointCs, pointB, dimH * 4);
  pointDs := shiftPoint(pointD, pointC, dimV * 4);
  pointDs := shiftPoint(pointDs, pointA, dimH * 4);

  result:=TIResultPointArray.Create(pointAs, pointBs, pointCs, pointDs);
end;

function TDataMatrixDetector.isValid(p: IResultPoint): Boolean;
begin
  Result := ((((p.X >= 0) and (p.X < Fimage.Width)) and (p.Y > 0)) and
    (p.Y < Fimage.Height))
end;

function TDataMatrixDetector.sampleGrid(image: TBitMatrix;
  topLeft, bottomLeft, bottomRight, topRight: IResultPoint;
  dimensionX, dimensionY: Integer): TBitMatrix;
begin
  // TGridSampler.instance
  Result := TDefaultGridSampler.sampleGrid(image, dimensionX, dimensionY, 0.5,
    0.5, (dimensionX - 0.5), 0.5, (dimensionX - 0.5), (dimensionY - 0.5), 0.5,
    (dimensionY - 0.5), topLeft.X, topLeft.Y, topRight.X, topRight.Y,
    bottomRight.X, bottomRight.Y, bottomLeft.X, bottomLeft.Y);
end;

/// <summary>
/// Counts the number of black/white transitions between two points, using something like Bresenham's algorithm.
/// </summary>
function TDataMatrixDetector.transitionsBetween(Afrom, Ato: IResultPoint)
  : integer;
var
  temp, fromX, fromY, toX, toY: Integer;
  steep: Boolean;
  dx, dy: Int64;
  xstep, ystep, Transitions: Integer;
  error: Int64;
  inBlack, isBlack: Boolean;
  X, Y: Integer;
begin
  // See QR Code Detector, sizeOfBlackWhiteBlackRun()
  fromX := Trunc(Afrom.X);
  fromY := Trunc(Afrom.Y);
  toX := Trunc(Ato.X);
  toY := Trunc(Ato.Y);
  steep := (Abs((toY - fromY)) > Abs((toX - fromX)));
  if (steep) then
  begin
    temp := fromX;
    fromX := fromY;
    fromY := temp;
    temp := toX;
    toX := toY;
    toY := temp;
  end;

  dx := Abs(toX - fromX);
  dy := Abs(toY - fromY);
  error := (-1*dx DIV 2);
  if (fromY < toY) then
    ystep := 1
  else
    ystep := -1;
  if (fromX < toX) then
    xstep := 1
  else
    xstep := -1;
  Transitions := 0;
  if steep then
    inBlack := Fimage[fromY, fromX]
  else
    inBlack := Fimage[fromX, fromY];

  X := fromX;
  Y := fromY;

  while ((X <> toX)) do
  begin
    if steep then
      isBlack := Fimage[Y, X]
    else
      isBlack := Fimage[X, Y];

    if (isBlack <> inBlack) then
    begin
      Inc(Transitions);
      inBlack := isBlack;
    end;
    Inc(error, dy);
    if (error > 0) then
    begin
      if (Y = toY) then
        break;
      Inc(Y, ystep);
      Dec(error, dx);
    end;
    Inc(X, xstep)
  end;

  Result := Transitions;
end;

function TDataMatrixDetector.detectSolid1(cornerPoints:TIResultPointArray):TIResultPointArray;
var
  pointA, pointB, pointC, pointD : IResultPoint;
  trAB,trBC,trCD,trDA            : integer;
  min                            : integer;
  points                         : TIResultPointArray;
begin
  // 0  2
  // 1  3
  pointA := cornerPoints[0];
  pointB := cornerPoints[1];
  pointC := cornerPoints[3];
  pointD := cornerPoints[2];

  trAB := transitionsBetween(pointA, pointB);
  trBC := transitionsBetween(pointB, pointC);
  trCD := transitionsBetween(pointC, pointD);
  trDA := transitionsBetween(pointD, pointA);

  // 0..3
  // :  :
  // 1--2
  min := trAB;

  points := TIResultPointArray.Create(pointD, pointA, pointB, pointC);

  if (min > trBC) then
  begin
    min := trBC;
    points[0] := pointA;
    points[1] := pointB;
    points[2] := pointC;
    points[3] := pointD;
  end;
  if (min > trCD) then
  begin
    min := trCD;
    points[0] := pointB;
    points[1] := pointC;
    points[2] := pointD;
    points[3] := pointA;
  end;
  if (min > trDA) then
  begin
    points[0] := pointC;
    points[1] := pointD;
    points[2] := pointA;
    points[3] := pointB;
  end;

  result:=points;
end;

function TDataMatrixDetector.detectSolid2(points:TIResultPointArray):TIResultPointArray;
var
  pointA, pointB, pointC, pointD : IResultPoint;
  pointBs, pointCs               : IResultPoint;
  tr,trBA,trCD                   : integer;
begin
  // A..D
  // :  :
  // B--C
  pointA := points[0];
  pointB := points[1];
  pointC := points[2];
  pointD := points[3];

  // Transition detection on the edge is not stable.
  // To safely detect, shift the points to the module center.
  tr := transitionsBetween(pointA, pointD);
  pointBs := shiftPoint(pointB, pointC, (tr + 1) * 4);
  pointCs := shiftPoint(pointC, pointB, (tr + 1) * 4);
  trBA := transitionsBetween(pointBs, pointA);
  trCD := transitionsBetween(pointCs, pointD);

  // 0..3
  // |  :
  // 1--2
  if (trBA < trCD) then
  begin
    // solid sides: A-B-C
    points[0] := pointA;
    points[1] := pointB;
    points[2] := pointC;
    points[3] := pointD;
  end
  else
  begin
    // solid sides: B-C-D
    points[0] := pointB;
    points[1] := pointC;
    points[2] := pointD;
    points[3] := pointA;
  end;

  result:=points;
end;

function TDataMatrixDetector.shiftPoint(point,_to:IResultPoint;_div:integer):IResultPoint;
var
  x,y:double;
begin
  x := (_to.X - point.X) / (_div + 1);
  y := (_to.Y - point.Y) / (_div + 1);
  result:=TResultPointHelpers.CreateResultPoint(point.X + x, point.Y + y);
end;

function TDataMatrixDetector.moveAway(point:IResultPoint;fromX,fromY:double):IResultPoint;
var
  x,y:double;
begin
  x := point.X;
  y := point.Y;

  if (x < fromX) then
    x:=x-1
  else
    x:=x+1;

  if (y < fromY) then
    y:=y-1
  else
    y:=y+1;

  result:=TResultPointHelpers.CreateResultPoint(x,y);
end;

end.
