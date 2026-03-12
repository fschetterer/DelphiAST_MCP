unit Tests.DelphiASTInvestigation;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDelphiASTInvestigationTests = class
  public
    [Test]
    procedure CompareIAnimalVsTAnimalChildren;
    [Test]
    procedure ParseAnimalsPas_Directly;
    [Test]
    procedure CheckAllTypesInAnimalsPas;
    [Test]
    procedure CheckUnitNameFromTree;
    [Test]
    procedure ParseAnimalsPas_ViaMCP;
    [Test]
    procedure GetAllParsedFiles;
    [Test]
    procedure CheckGetAllTreesAfterWait;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Json,
  DelphiAST, DelphiAST.Classes, DelphiAST.Consts,
  MCP.TestHelper;

{ Helper function to get node type name }
function NodeTypeName(Node: TSyntaxNode): string;
begin
  Result := SyntaxNodeNames[Node.Typ];
end;

{ Helper function to get node name }
function NodeName(Node: TSyntaxNode): string;
begin
  Result := Node.GetAttribute(anName);
  if (Result = '') and (Node is TValuedSyntaxNode) then
    Result := TValuedSyntaxNode(Node).Value;
end;

procedure TDelphiASTInvestigationTests.CompareIAnimalVsTAnimalChildren;
var
  FileName: string;
  Tree, TypeDecl, TypeNode, Child: TSyntaxNode;
  Output: TStringList;
  TypName: string;
  NamName: string;
  I: Integer;
begin
  FileName := ExtractFilePath(ParamStr(0)) + '..\tests\test-project\Animals.pas';

  Tree := TPasSyntaxTreeBuilder.Run(FileName, False, nil);
  try
    Assert.IsNotNull(Tree, 'Tree should not be nil');

    Output := TStringList.Create;
    try
      Output.Add('=== Comparing IAnimal vs TAnimal type node children ===');

      // Find both IAnimal and TAnimal
      for TypeDecl in Tree.ChildNodes do
      begin
        if TypeDecl.Typ = ntTypeDecl then
        begin
          var TypeName := NodeName(TypeDecl);

          if SameText(TypeName, 'IAnimal') or SameText(TypeName, 'TAnimal') then
          begin
            Output.Add(Format('=== %s ===', [TypeName]));

            // Get the inner type node
            TypeNode := TypeDecl.FindNode(ntType);
            if Assigned(TypeNode) then
            begin
              Output.Add(Format('Type node name: "%s"', [NodeName(TypeNode)]));
              Output.Add(Format('Children of Type node (%d):', [Length(TypeNode.ChildNodes)]));
              for Child in TypeNode.ChildNodes do
              begin
                TypName := NodeTypeName(Child);
                NamName := NodeName(Child);
                Output.Add(Format('  - [%s] name="%s"', [TypName, NamName]));
              end;
            end;
            Output.Add('');
          end;
        end;
      end;

      // Write to console
      for I := 0 to Output.Count - 1 do
        System.Writeln(Output[I]);

    finally
      Output.Free;
    end;
  finally
    Tree.Free;
  end;
end;

procedure TDelphiASTInvestigationTests.ParseAnimalsPas_Directly;
var
  FileName: string;
  Tree: TSyntaxNode;
begin
  FileName := ExtractFilePath(ParamStr(0)) + '..\tests\test-project\Animals.pas';

  Assert.IsTrue(FileExists(FileName), 'Animals.pas should exist at: ' + FileName);

  Tree := TPasSyntaxTreeBuilder.Run(FileName, False, nil);
  try
    Assert.IsNotNull(Tree, 'Tree should not be nil');
    System.Writeln('ParseAnimalsPas_Directly: Successfully parsed Animals.pas');
    System.Writeln('  Root node type: ', NodeTypeName(Tree));
  finally
    Tree.Free;
  end;
end;

procedure TDelphiASTInvestigationTests.CheckAllTypesInAnimalsPas;
var
  FileName: string;
  Tree, Child, TypeDecl: TSyntaxNode;
  FoundTypes: TStringList;
begin
  FileName := ExtractFilePath(ParamStr(0)) + '..\tests\test-project\Animals.pas';

  Tree := TPasSyntaxTreeBuilder.Run(FileName, False, nil);
  try
    System.Writeln('CheckAllTypesInAnimalsPas: Root has ', Length(Tree.ChildNodes), ' children');

    // Debug: Print first level children
    for Child in Tree.ChildNodes do
    begin
      System.Writeln('  Child: [', NodeTypeName(Child), '] name="', NodeName(Child), '"');
    end;

    // Find the interface section
    var IntfNode := Tree.FindNode(ntInterface);
    if Assigned(IntfNode) then
    begin
      System.Writeln('  Interface section has ', Length(IntfNode.ChildNodes), ' children');
      for Child in IntfNode.ChildNodes do
      begin
        System.Writeln('    Intf child: [', NodeTypeName(Child), '] name="', NodeName(Child), '"');
      end;
    end;

    FoundTypes := TStringList.Create;
    try
      // Collect all type declarations from interface section
      if Assigned(IntfNode) then
      begin
        for TypeDecl in IntfNode.ChildNodes do
        begin
          if TypeDecl.Typ = ntTypeDecl then
          begin
            var TypeName := NodeName(TypeDecl);
            System.Writeln('    Found type: ', TypeName);
            if TypeName <> '' then
              FoundTypes.Add(TypeName);
          end
          else
          if TypeDecl.Typ = ntTypeSection then
          begin
            // TypeSection contains multiple type declarations
            for var SecChild in TypeDecl.ChildNodes do
            begin
              if SecChild.Typ = ntTypeDecl then
              begin
                var TypeName := NodeName(SecChild);
                System.Writeln('    Found type in section: ', TypeName);
                if TypeName <> '' then
                  FoundTypes.Add(TypeName);
              end;
            end;
          end;
        end;
      end;

      System.Writeln('CheckAllTypesInAnimalsPas: Found types count: ', FoundTypes.Count);

      // Check for specific types
      Assert.IsTrue(FoundTypes.IndexOf('IAnimal') >= 0, 'Should find IAnimal');
      Assert.IsTrue(FoundTypes.IndexOf('TAnimal') >= 0, 'Should find TAnimal');
      Assert.IsTrue(FoundTypes.IndexOf('TAnimalKind') >= 0, 'Should find TAnimalKind');

      System.Writeln('  IAnimal: found');
      System.Writeln('  TAnimal: found');
      System.Writeln('  TAnimalKind: found');
    finally
      FoundTypes.Free;
    end;
  finally
    Tree.Free;
  end;
end;

procedure TDelphiASTInvestigationTests.CheckUnitNameFromTree;
var
  FileName: string;
  Tree: TSyntaxNode;
  UnitName: string;
begin
  FileName := ExtractFilePath(ParamStr(0)) + '..\tests\test-project\Animals.pas';

  Tree := TPasSyntaxTreeBuilder.Run(FileName, False, nil);
  try
    UnitName := NodeName(Tree);
    System.Writeln('CheckUnitNameFromTree: Unit name = "', UnitName, '"');

    Assert.AreEqual('Animals', UnitName, 'Unit name should be Animals');
  finally
    Tree.Free;
  end;
end;

procedure TDelphiASTInvestigationTests.ParseAnimalsPas_ViaMCP;
var
  Args: TJSONObject;
  Result: TJSONValue;
  Obj: TJSONObject;
begin
  // Test via MCP server - this is what the failing tests do
  Args := TJSONObject.Create;
  Args.AddPair('file', 'Animals.pas');
  try
    Result := TMCPTestHelper.CallTool('parse_unit', Args);
    try
      Assert.IsNotNull(Result, 'Result is nil');
      System.Writeln('ParseAnimalsPas_ViaMCP: Result = ', Result.ToString);

      if Result is TJSONObject then
      begin
        Obj := TJSONObject(Result);
        var UnitName := Obj.GetValue<string>('unit_name', '(not found)');
        System.Writeln('  unit_name: ', UnitName);
        var TypesVal := Obj.GetValue('types');
        if Assigned(TypesVal) then
          System.Writeln('  types: ', TypesVal.ToString)
        else
          System.Writeln('  types: (not found)');
      end
      else
        System.Writeln('  Result is not TJSONObject: ', Result.ClassName);
    finally
      Result.Free;
    end;
  finally
    Args.Free;
  end;
end;

procedure TDelphiASTInvestigationTests.GetAllParsedFiles;
var
  Result: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
begin
  // Get all parsed files - this shows what's in the cache
  Result := TMCPTestHelper.CallTool('parse_unit');
  try
    Assert.IsNotNull(Result, 'Result is nil');
    System.Writeln('GetAllParsedFiles: Result = ', Result.ToString);

    if Result is TJSONArray then
    begin
      Arr := TJSONArray(Result);
      System.Writeln('  Found ', Arr.Count, ' parsed files:');
      for I := 0 to Arr.Count - 1 do
      begin
        if Arr[I] is TJSONObject then
        begin
          var FileObj := TJSONObject(Arr[I]);
          var FileName := FileObj.GetValue<string>('file', '(unknown)');
          System.Writeln('    - ', FileName);
        end;
      end;
    end
    else
      System.Writeln('  Result is not TJSONArray: ', Result.ClassName);
  finally
    Result.Free;
  end;
end;

procedure TDelphiASTInvestigationTests.CheckGetAllTreesAfterWait;
var
  Result: TJSONValue;
  Obj: TJSONObject;
begin
  // After WaitForParseComplete, check what files are returned by parse_unit without file param
  // This simulates what get_type_detail does
  Result := TMCPTestHelper.CallTool('parse_unit');
  try
    Assert.IsNotNull(Result, 'Result is nil');
    System.Writeln('CheckGetAllTreesAfterWait: Result = ', Result.ToString);
  finally
    Result.Free;
  end;
end;

end.
