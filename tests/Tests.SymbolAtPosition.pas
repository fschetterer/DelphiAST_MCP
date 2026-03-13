unit Tests.SymbolAtPosition;

interface

uses
  DUnitX.TestFramework, System.JSON;

type
  [TestFixture]
  TSymbolAtPositionTests = class
  public
    [Test]
    procedure TDogClassLine_ReturnsTDog;
  end;

implementation

uses
  MCP.TestHelper;

procedure TSymbolAtPositionTests.TDogClassLine_ReturnsTDog;
var
  Args: TJSONObject;
  Result: TJSONValue;
  Obj: TJSONObject;
begin
  Args := TJSONObject.Create;
  Args.AddPair('file', 'Dog.pas');
  Args.AddPair('line', TJSONNumber.Create(9)); // TDog = class(TAnimal) is around line 9
  Args.AddPair('col', TJSONNumber.Create(3)); // Column where TDog starts (after 2 spaces indentation)
  try
    Result := TMCPTestHelper.CallTool('symbol_at_position', Args);
    try
      Assert.IsNotNull(Result, 'Result is nil');
      Assert.IsTrue(Result is TJSONObject, 'Result should be a TJSONObject but was: ' + Result.ClassName);
      Obj := TJSONObject(Result);
      // Should find TDog class
      TMCPTestHelper.AssertStringContains(Obj.ToString, 'TDog');
    finally
      Result.Free;
    end;
  finally
    Args.Free;
  end;
end;

end.
