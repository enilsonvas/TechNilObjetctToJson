# TechNil.ObjToJson.Helpers

**TechNil.ObjToJson.Helpers** é uma unit Delphi que estende `TObject` e `TDataSet` com métodos genéricos para:

- Converter facilmente objetos para JSON e vice-versa  
- Serializar listas de objetos em `TJSONArray`  
- Mapear diretamente campos de um `TDataSet` para as propriedades de um objeto  
- Preencher um `TDataSet` a partir de um objeto, respeitando tipos e ignorando campos  

Ideal para aplicações que consomem APIs REST, armazenam dados em JSON ou sincronizam registros entre datasets e modelos de objeto.

---

## Recursos Principais

- Conversão JSON ↔ Objeto  
  - LoadFromJsonString, LoadFromJSON, LoadFromJsonArray  
  - ToJsonObject, ToJsonArray, ToJsonString  
- Mapeamento de `TDataSet` ↔ Objeto  
  - `TObject.LoadFromDataSet` preenche propriedades públicas a partir de um dataset  
  - `TDataSet.LoadFromObject` popula o dataset com valores de um objeto  
- Suporte a tipos avançados  
  - Datas em ISO 8601 com opção UTC  
  - Propriedades booleanas, enums e numéricas  
  - `TStream` e `TMemoryStream` convertidos para Base64  
  - Listas genéricas (`TObjectList<T>`, `TList<T>`) tratadas recursivamente  
- Tratamento de incompatibilidades  
  - Exceções específicas (`EIncompatibilidadeTipo`) para campos que não convergem  

---

## Configuração de Formatação

A classe `TJsonHelpersOptions` permite controlar formato de nome de propriedade e fuso de data:

```pascal
type
  TpCase = (tpcNone, tpcFirstWordLower, tpcLower, tpcUpper);

  TJsonHelpersOptions = class
  public
    isUTC: Boolean;          // true = datas em UTC, false = horário local
    CaseFormat: TpCase;      // conversão de maiúsculas/minúsculas
    constructor Create;
    function FormatNameProp(aName: string): string;
    function GetUTC: Boolean;
  end;
```

| CaseFormat           | Exemplo            |
|----------------------|--------------------|
| tpcNone              | NomeCliente        |
| tpcFirstWordLower    | nomeCliente        |
| tpcLower             | nomecliente        |
| tpcUpper             | NOMECLIENTE        |

---

## Exemplos de Uso

### Serializar Objeto para JSON

```pascal
var
  Cliente: TCliente;
  JsonText: string;
begin
  Cliente := TCliente.Create;
  try
    Cliente.Id := 42;
    Cliente.Nome := 'Maria';
    JsonText := Cliente.ToJsonString;
// JsonText = '{"Id":42,"Nome":"Maria"}'
  finally
    Cliente.Free;
  end;
end;
```

### Desserializar JSON em Objeto

```pascal
var
  Cliente: TCliente;
  JsonText: string;
  Options: TJsonHelpersOptions;
begin
  JsonText := '{"Id":13,"Nome":"Paulo","DataNasc":"2023-01-15T00:00:00Z"}';
  Cliente := TCliente.Create;
  Options := TJsonHelpersOptions.Create;
  try
    Options.isUTC := True;
    Options.CaseFormat := tpcNone;
    Cliente.LoadFromJsonString(JsonText, Options);
// Cliente.Id = 13, Cliente.Nome = 'Paulo', Cliente.DataNasc = ISO8601ToDate(...)
  finally
    Options.Free;
    Cliente.Free;
  end;
end;
```

### Mapear `TDataSet` para Objeto

```pascal
var
  Query: TFDQuery;
  Pedido: TPedido;
begin
  Query.Open('SELECT * FROM Pedidos WHERE Id=:Id', [123]);
  Pedido := TPedido.Create;
  try
    Pedido.LoadFromDataSet(Query, ['Senha']);
// Propriedade Senha será ignorada no mapeamento
  finally
    Pedido.Free;
    Query.Close;
  end;
end;
```

### Carregar `TDataSet` a partir de Objeto

```pascal
var
  Query: TFDTable;
  Cliente: TCliente;
begin
  Query.Open('Clientes');
  Cliente := TCliente.Create;
  try
    Cliente.Id := 77;
    Cliente.Nome := 'Ana';
    Query.LoadFromObject(Cliente, ['Senha']);
// Insere ou atualiza campos do DataSet com valores de Cliente, exceto Senha
  finally
    Cliente.Free;
    Query.Close;
  end;
end;
```

---

## Considerações

- Apenas propriedades públicas/published são processadas.  
- Propriedades nulas, vazias ou com valor padrão são ignoradas ao popular dataset.  
- Exceções customizadas sinalizam incompatibilidade de tipo entre campo e propriedade.  
- Listas e objetos aninhados são tratados de forma recursiva.  

---

## Instalação

1. Copie `TechNil.ObjToJson.Helpers.pas` para a pasta de units do seu projeto.  
2. Inclua `TechNil.ObjToJson.Helpers` na cláusula `uses`.  
3. Chame os métodos helper conforme sua necessidade.  

---

## Licença

Este projeto está distribuído sob a Licença MIT. Pode ser utilizado livremente em projetos pessoais ou comerciais.
