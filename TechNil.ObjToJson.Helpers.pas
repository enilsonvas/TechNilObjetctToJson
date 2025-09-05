unit TechNil.ObjToJson.Helpers;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Rtti,
  System.TypInfo,
  System.DateUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.NetEncoding,
  Data.DB,
  System.StrUtils;

type
  EIncompatibilidadeTipo = class(Exception)
  public
    constructor Create(const Campo, TipoEsperado, TipoRecebido: string);
  end;

  TpCase = (tpcNone, tpcFirstWordLower, tpcLower, tpcUpper);

  TJsonHelpersOptions = class
  private
    function FormatNameProp(aName: string): string;
    function GetUTC: Boolean;
  public
    isUTC: Boolean;
    CaseFormat: TpCase;
  published
    constructor Create;
  end;

  TJsonHelpers = class helper for TObject
  private
    function StreamFromBase64(aStream : TStream) : string;
    procedure Base64FromStream(aBase64 : string; aStream : TStream);
  public
    procedure LoadFromDataSet(Lds: TDataSet; const CamposIgnorados: TArray<string>=[]);

    procedure LoadFromJsonString(const JsonText: string; aOptions: TJsonHelpersOptions=nil);
    procedure LoadFromJSON(const JsonObj: TJSONObject; aOptions: TJsonHelpersOptions=nil);
    procedure LoadFromJsonArray(const JsonArr: TJSONArray; aOptions: TJsonHelpersOptions=nil);

    function  ToJsonObject(aOptions: TJsonHelpersOptions=nil): TJSONObject;
    function  ToJsonArray(aOptions: TJsonHelpersOptions=nil): TJSONArray;
    function  ToJsonString(aOptions: TJsonHelpersOptions=nil): string;
  end;

  TDataSetHelper = class helper for TDataSet
  public
    /// <summary>
    ///  Preenche os campos do TDataSet com valores das propriedades públicas de um objeto.
    ///  Campos cujo nome estiver em CamposIgnorados serão pulados.
    /// </summary>
    procedure LoadFromObject(aObj: TObject; const CamposIgnorados: TArray<string> = []);
  end;

implementation

{ TJsonHelpers }

procedure TJsonHelpers.LoadFromJsonString(const JsonText: string; aOptions: TJsonHelpersOptions=nil);
var
  JVal: TJSONValue;
begin
  JVal := TJSONObject.ParseJSONValue(JsonText);
  try
    if JVal is TJSONObject then
      LoadFromJSON(TJSONObject(JVal), aOptions)
    else if JVal is TJSONArray then
      LoadFromJsonArray(TJSONArray(JVal), aOptions)
    else
      raise EJsonException.Create('JSON inválido para carregar em objeto');
  finally
    JVal.Free;
  end;
end;

function TJsonHelpers.StreamFromBase64(aStream: TStream): string;
var
  EncodedStream : TStringStream;
begin
  EncodedStream := TStringStream.Create;
  try
    TNetEncoding.Base64String.Encode(aStream, EncodedStream);
    Result := EncodedStream.DataString;
  finally
    FreeAndNil(EncodedStream);
  end;
end;

procedure TJsonHelpers.Base64FromStream(aBase64: string; aStream: TStream);
var
  Base64Stream : TStringStream;
begin
  Base64Stream := TStringStream.Create(aBase64);
  try
    aStream.Position := 0;
    Base64Stream.Position := 0;
    TNetEncoding.Base64String.Decode(Base64Stream, aStream);
  finally
    FreeAndNil(Base64Stream);
  end;
end;

procedure TJsonHelpers.LoadFromJSON(const JsonObj: TJSONObject; aOptions: TJsonHelpersOptions=nil);
var
  Ctx         : TRttiContext;
  Typ         : TRttiType;
  Prop        : TRttiProperty;
  Pair        : TJSONPair;
  JsonVal     : TJSONValue;
  LowerName   : string;
  ValueObj    : TObject;
  RListType   : TRttiType;
  CountProp   : TRttiProperty;
  AddMethod   : TRttiMethod;
  ElType      : TRttiType;
  E           : TJSONValue;
  NewObj      : TObject;
  ClearMethod : TRttiMethod;
  PropName    : string;
begin
  Ctx := TRttiContext.Create;
  try
    Typ := Ctx.GetType(Self.ClassType);
    for Pair in JsonObj do
    begin
      JsonVal   := Pair.JsonValue;
      LowerName := LowerCase(Pair.JsonString.Value);

      for Prop in Typ.GetProperties do
      begin
        PropName := Prop.Name;

        if Assigned(aOptions) then
          PropName := aOptions.FormatNameProp(PropName);

        if Prop.IsWritable and
          ((SameText(PropName, Pair.JsonString.Value)) or
           (LowerCase(PropName) = LowerName)) then
        begin
          case Prop.PropertyType.TypeKind of
            tkInteger:
              Prop.SetValue(Self, JsonVal.Value.ToInteger);
            tkInt64:
              Prop.SetValue(Self, JsonVal.Value.ToInt64);
            tkFloat:
              begin
                if Prop.PropertyType.Handle = TypeInfo(TDateTime) then
                  begin
                    if Assigned(aOptions) then
                      Prop.SetValue(Self, ISO8601ToDate(JsonVal.Value, aOptions.GetUTC))
                    else
                      Prop.SetValue(Self, ISO8601ToDate(JsonVal.Value));
                  end
                else
                  begin
                    if TFormatSettings.Create.CurrencyString = 'R$' then
                      Prop.SetValue(Self, StrToFloat(StringReplace(JsonVal.Value, '.', ',', [rfReplaceAll])))
                    else
                      Prop.SetValue(Self, StrToFloatDef(JsonVal.Value, 0));
                  end;
              end;
            tkString, tkLString, tkWString, tkUString:
              Prop.SetValue(Self, JsonVal.Value);
            tkEnumeration:
              if Prop.PropertyType.Handle = TypeInfo(Boolean) then
                Prop.SetValue(Self, JsonVal.Value.ToBoolean)
              else
                Prop.SetValue(Self,
                  TValue.FromOrdinal(
                    Prop.PropertyType.Handle,
                    GetEnumValue(
                      Prop.PropertyType.Handle,
                      JsonVal.Value
                    )
                  )
                );
            tkClass:
              begin
                if (Prop.GetValue(Pointer(Self)).AsObject.InheritsFrom(TStream)) or
                   (Prop.GetValue(Pointer(Self)).AsObject.InheritsFrom(TMemoryStream)) then
                  begin
                    if Assigned(JsonVal) then
                      Base64FromStream(JsonVal.Value, TStream(Prop.GetValue(Pointer(Self)).AsObject));
                  end
                else
                  begin
                    // detecta lista genérica (TList<T> / TObjectList<T>)
                    ValueObj := Prop.GetValue(Self).AsObject;
                    if not Assigned(ValueObj) then
                      Break;

                    RListType := Ctx.GetType(ValueObj.ClassType);
                    CountProp := RListType.GetProperty('Count');
                    AddMethod := RListType.GetMethod('Add');

                    if (JsonVal is TJSONArray) and
                       Assigned(CountProp) and
                       Assigned(AddMethod) then
                    begin
                      // limpa a lista
                      ClearMethod := RListType.GetMethod('Clear');
                      if Assigned(ClearMethod) then
                        ClearMethod.Invoke(ValueObj, []);

                      // pega tipo do elemento para instanciar
                      ElType := (AddMethod.GetParameters[0].ParamType as TRttiInstanceType);
                      for E in TJSONArray(JsonVal) do
                      begin
                        if ElType is TRttiInstanceType then
                        begin
                          NewObj := TRttiInstanceType(ElType).MetaclassType.Create;
                          try
                            if E is TJSONObject then
                              NewObj.LoadFromJSON(E as TJSONObject, aOptions);
                          except
                            FreeAndNil(NewObj);
                            raise;
                          end;
                          // adiciona à lista
                          AddMethod.Invoke(ValueObj, [NewObj]);
                        end;
                      end;
                    end
                    else if JsonVal is TJSONObject then
                      // objeto aninhado comum
                      ValueObj.LoadFromJSON(JsonVal as TJSONObject, aOptions)
                    else if JsonVal is TJSONArray then
                      // array atribuído a objeto
                      ValueObj.LoadFromJsonArray(JsonVal as TJSONArray, aOptions);
                  end;
              end;
          else
            Prop.SetValue(Self, JsonVal.Value);
          end;
          Break;
        end;
      end;
    end;
  finally
    Ctx.Free;
  end;
end;

procedure TJsonHelpers.LoadFromJsonArray(const JsonArr: TJSONArray; aOptions: TJsonHelpersOptions=nil);
var
  Ctx       : TRttiContext;
  Typ       : TRttiType;
  CountProp : TRttiProperty;
  AddMethod : TRttiMethod;
  ClearMeth : TRttiMethod;
  ElType    : TRttiInstanceType;
  E         : TJSONValue;
  NewObj    : TObject;
  Props     : TArray<TRttiProperty>;
  Prop      : TRttiProperty;
  I         : Integer;
  JsonV     : TJSONValue;
  tmpObj    : TJSONObject;
begin
  Ctx := TRttiContext.Create;
  try
    Typ := Ctx.GetType(Self.ClassType);

    // Detecta se é uma lista genérica
    CountProp := Typ.GetProperty('Count');
    AddMethod := Typ.GetMethod('Add');
    if Assigned(CountProp) and Assigned(AddMethod) then
    begin
      // Limpa lista
      ClearMeth := Typ.GetMethod('Clear');
      if Assigned(ClearMeth) then
        ClearMeth.Invoke(Self, []);

      // Tipo do elemento
      if AddMethod.GetParameters[0].ParamType is TRttiInstanceType then
        ElType := TRttiInstanceType(AddMethod.GetParameters[0].ParamType)
      else
        ElType := nil;

      for E in JsonArr do
      begin
        if Assigned(ElType) and (E is TJSONObject) then
        begin
          NewObj := ElType.MetaclassType.Create;
          try
            NewObj.LoadFromJSON(E as TJSONObject, aOptions);
          except
            NewObj.Free;
            raise;
          end;
          AddMethod.Invoke(Self, [NewObj]);
        end;
      end;
      Exit; // já tratou como lista
    end;

    // Caso não seja lista, mapeia por ordem alfabética das propriedades
    Props := Typ.GetProperties;
    TArray.Sort<TRttiProperty>(Props,
      TComparer<TRttiProperty>.Construct(
        function(const A, B: TRttiProperty): Integer
        begin
          Result := CompareText(A.Name, B.Name);
        end
      )
    );

    for I := 0 to High(Props) do
    begin
      if I >= JsonArr.Count then
        Break;
      Prop := Props[I];
      if not Prop.IsWritable then
        Continue;

      JsonV := JsonArr.Items[I];
      if JsonV is TJSONObject then
        Prop.GetValue(Self).AsObject.LoadFromJSON(JsonV as TJSONObject, aOptions)
      else
      begin
        tmpObj := TJSONObject.Create;
        try
          tmpObj.AddPair(Prop.Name, JsonV.Clone as TJSONValue);
          LoadFromJSON(tmpObj, aOptions);
        finally
          tmpObj.Free;
        end;
      end;
    end;
  finally
    Ctx.Free;
  end;
end;

function TJsonHelpers.ToJsonObject(aOptions: TJsonHelpersOptions=nil): TJSONObject;
var
  Ctx         : TRttiContext;
  Typ         : TRttiType;
  Prop        : TRttiProperty;
  Name        : string;
  JVal        : TJSONValue;
  ValueObj    : TObject;
  RListType   : TRttiType;
  CountProp   : TRttiProperty;
  GetItem     : TRttiMethod;
  ListCount   : Integer;
  I           : Integer;
  ItemValue   : TValue;
  ItemObj     : TObject;
  JArr        : TJSONArray;
  UTCDef      : Boolean;
begin
  Result := TJSONObject.Create;
  Ctx    := TRttiContext.Create;

  UTCDef := true;

  try
    Typ := Ctx.GetType(Self.ClassType);

    for Prop in Typ.GetProperties do
    begin
      if not Prop.IsReadable then
        Continue;

      Name := Prop.Name;

      if Assigned(aOptions) then
        begin
          Name := aOptions.FormatNameProp(Name);
          UTCDef := aOptions.GetUTC;
        end;


      case Prop.PropertyType.TypeKind of
        tkInteger, tkInt64:
          Result.AddPair(Name,
            TJSONNumber.Create(Prop.GetValue(Self).AsInteger)
          );

        tkFloat:
          if Prop.PropertyType.Handle = TypeInfo(TDateTime) then
            begin
              Result.AddPair(Name,
                TJSONString.Create(
                  DateToISO8601(
                    Prop.GetValue(Self).AsType<TDateTime>, UTCDef
                  )
                )
              )
            end
          else
            Result.AddPair(Name,
              TJSONNumber.Create(
                Prop.GetValue(Self).AsExtended
              )
            );

        tkString, tkLString, tkWString, tkUString:
          Result.AddPair(Name,
            TJSONString.Create(Prop.GetValue(Self).AsString)
          );

        tkEnumeration:
          if Prop.PropertyType.Handle = TypeInfo(Boolean) then
            Result.AddPair(Name,
              TJSONBool.Create(Prop.GetValue(Self).AsBoolean)
            )
          else
            Result.AddPair(Name,
              TJSONString.Create(Prop.GetValue(Self).ToString)
            );

        tkClass:
          begin
            ValueObj := Prop.GetValue(Self).AsObject;
            if not Assigned(ValueObj) then
            begin
              Result.AddPair(Name, TJSONNull.Create);
              Continue;
            end;

            if (ValueObj.InheritsFrom(TMemoryStream)) or (ValueObj.InheritsFrom(TStream)) then
              Result.AddPair(Name, StreamFromBase64(TStream(ValueObj)))
            else
              begin
                // detecta lista genérica
                RListType := Ctx.GetType(ValueObj.ClassType);
                CountProp := RListType.GetProperty('Count');
                GetItem   := RListType.GetMethod('GetItem');

                if Assigned(CountProp) and Assigned(GetItem) then
                begin
                  JArr      := TJSONArray.Create;
                  ListCount := CountProp.GetValue(ValueObj).AsInteger;
                  for I := 0 to ListCount - 1 do
                  begin
                    ItemValue := GetItem.Invoke(ValueObj, [I]);
                    ItemObj   := ItemValue.AsObject;
                    if Assigned(ItemObj) then
                      JArr.AddElement(ItemObj.ToJsonObject(aOptions))
                    else
                      JArr.AddElement(TJSONNull.Create);
                  end;
                  Result.AddPair(Name, JArr);
                end
                else
                begin
                  // objeto aninhado comum
                  JVal := ValueObj.ToJsonObject(aOptions);
                  Result.AddPair(Name, JVal);
                end;
              end;
          end;
      else
        Result.AddPair(Name,
          TJSONString.Create(Prop.GetValue(Self).ToString)
        );
      end;
    end;
  finally
    Ctx.Free;
  end;
end;

function TJsonHelpers.ToJsonArray(aOptions: TJsonHelpersOptions=nil): TJSONArray;
var
  Objeto : TObject;
begin
  if not Self.ClassName.ToLower.Contains('tobjectlist<') then
    raise EJsonException.Create('O Objeto não é um TObjectList<T> para gerar um JSONArray válido!');

  Result := TJSONArray.Create;

  for Objeto in TObjectList<TObject>(Self) do
    begin
      Result.AddElement(Objeto.ToJsonObject(aOptions));
    end;
end;

function TJsonHelpers.ToJsonString(aOptions: TJsonHelpersOptions=nil): string;
var
  JObj: TJSONObject;
begin
  JObj := ToJsonObject(aOptions);
  try
    Result := JObj.ToString;
  finally
    JObj.Free;
  end;
end;

procedure TJsonHelpers.LoadFromDataSet(Lds: TDataSet;
  const CamposIgnorados: TArray<string>);
var
  ctx: TRttiContext;
  rType: TRttiType;
  prop: TRttiProperty;
  i: Integer;
  IgnoradosUpper: TArray<string>;
  field: TField;
  defaultStream: TMemoryStream;
begin
  ctx := TRttiContext.Create;
  try
    rType := ctx.GetType(Self.ClassType);

    // Monta lista de campos ignorados em uppercase
    SetLength(IgnoradosUpper, Length(CamposIgnorados));
    for i := 0 to High(CamposIgnorados) do
      IgnoradosUpper[i] := UpperCase(CamposIgnorados[i]);

    for i := 0 to Lds.FieldCount - 1 do
    begin
      field := Lds.Fields[i];

      // Se for pra ignorar, pula
      if (Length(IgnoradosUpper) > 0) and
         MatchText(UpperCase(field.FieldName), IgnoradosUpper) then
        Continue;

      prop := rType.GetProperty(field.FieldName);
      if not Assigned(prop) or not prop.IsWritable then
        Continue;

      // Se for nulo, atribui um default
      if field.IsNull then
      begin
        Continue;
      end;

      // Mapeamento normal conforme tipo
      case field.DataType of
        ftInteger, ftSmallint, ftWord, ftAutoInc:
          prop.SetValue(Self, TValue.From<Integer>(field.AsInteger));
        ftFloat, ftCurrency, ftBCD:
          prop.SetValue(Self, TValue.From<Double>(field.AsFloat));
        ftString, ftWideString, ftMemo:
          prop.SetValue(Self, TValue.From<string>(field.AsString));
        ftDate, ftTime, ftDateTime, ftTimeStamp:
          prop.SetValue(Self, TValue.From<TDateTime>(field.AsDateTime));
        ftBlob:
          begin
            if prop.PropertyType.IsInstance and
               prop.PropertyType.AsInstance.MetaclassType.InheritsFrom(TStream) then
            begin
              defaultStream := TMemoryStream.Create;
              try
                (field as TBlobField).SaveToStream(defaultStream);
                defaultStream.Position := 0;
                prop.SetValue(Self, TValue.From<TStream>(defaultStream));
              except
                defaultStream.Free;
                raise;
              end;
            end
            else
              prop.SetValue(Self, TValue.From<string>(field.AsString));
          end;
      end;
    end;
  finally
    ctx.Free;
  end;
end;

{ TJsonHelpersOptions }

constructor TJsonHelpersOptions.Create;
begin
  isUTC      := True;
  CaseFormat := tpcNone;
end;

function TJsonHelpersOptions.FormatNameProp(aName: string): string;
begin
  case CaseFormat of
    tpcNone          : Result := aName;
    tpcFirstWordLower: Result := LowerCase(aName.Chars[0]) + aName.Remove(0, 1);
    tpcLower         : Result := aName.ToLower;
    tpcUpper         : Result := aName.ToUpper;
  end;
end;

function TJsonHelpersOptions.GetUTC: Boolean;
begin
  Result := isUTC;
end;

{ TDataSetHelper }

procedure TDataSetHelper.LoadFromObject(aObj: TObject; const CamposIgnorados: TArray<string> = []);
var
  ctx: TRttiContext;
  rType: TRttiType;
  prop: TRttiProperty;
  value: TValue;
  i: Integer;
  IgnoradosUpper: TArray<string>;
  field: TField;
  tempInt: Integer;
  tempFloat: Extended;
  tempStr: string;
  tempBool: Boolean;
  tempDate: TDateTime;
begin
  rType := ctx.GetType(aObj.ClassType);

  SetLength(IgnoradosUpper, Length(CamposIgnorados));
  for i := 0 to High(CamposIgnorados) do
    IgnoradosUpper[i] := UpperCase(CamposIgnorados[i]);

  for i := 0 to FieldCount - 1 do
  begin
    field := Fields[i];

    if MatchText(UpperCase(field.FieldName), IgnoradosUpper) then
      Continue;

    prop := rType.GetProperty(field.FieldName);
    if not Assigned(prop) or not prop.IsReadable then
      Continue;

    value := prop.GetValue(aObj);

    // Ignora valores nulos, vazios ou padrão
    if value.IsEmpty or
       ((value.Kind = tkString) and value.AsString.Trim.IsEmpty) or
       ((value.Kind = tkClass) and (value.AsObject = nil)) or
       ((value.Kind = tkInteger) and (value.AsInteger = 0)) or
       ((value.Kind = tkFloat) and (value.AsExtended = 0.0)) then
      Continue;

    // Verifica compatibilidade e atribui
    case field.DataType of
      ftInteger, ftSmallint, ftWord, ftAutoInc:
        if value.TryAsType<Integer>(tempInt) then
          field.AsInteger := tempInt
        else
          raise EIncompatibilidadeTipo.Create(field.FieldName, 'Integer', value.TypeInfo.Name);

      ftFloat, ftCurrency, ftBCD:
        if value.TryAsType<Extended>(tempFloat) then
          field.AsFloat := tempFloat
        else
          raise EIncompatibilidadeTipo.Create(field.FieldName, 'Float', value.TypeInfo.Name);

      ftString, ftWideString, ftMemo:
        if value.TryAsType<string>(tempStr) then
          field.AsString := tempStr
        else
          raise EIncompatibilidadeTipo.Create(field.FieldName, 'String', value.TypeInfo.Name);

      ftDate, ftTime, ftDateTime, ftTimeStamp:
        if value.TryAsType<TDateTime>(tempDate) then
          field.AsDateTime := tempDate
        else
          raise EIncompatibilidadeTipo.Create(field.FieldName, 'DateTime', value.TypeInfo.Name);

      ftBoolean:
        if value.TryAsType<Boolean>(tempBool) then
          field.AsBoolean := tempBool
        else
          raise EIncompatibilidadeTipo.Create(field.FieldName, 'Boolean', value.TypeInfo.Name);

      ftBlob:
        if value.IsObject and (value.AsObject is TStream) then
        begin
          if TStream(value.AsObject).Size > 0 then
            (field as TBlobField).LoadFromStream(TStream(value.AsObject));
        end
        else if value.TryAsType<string>(tempStr) then
          field.Value := tempStr
        else
          raise EIncompatibilidadeTipo.Create(field.FieldName, 'TStream ou String', value.TypeInfo.Name);
    else
      raise EIncompatibilidadeTipo.Create(field.FieldName, 'Tipo suportado', FieldTypeNames[field.DataType]);
    end;
  end;
end;

{ EIncompatibilidadeTipo }

constructor EIncompatibilidadeTipo.Create(const Campo, TipoEsperado,
  TipoRecebido: string);
begin
  inherited CreateFmt('Incompatibilidade de tipo no campo "%s": esperado %s, recebido %s',
    [Campo, TipoEsperado, TipoRecebido]);
end;

end.
