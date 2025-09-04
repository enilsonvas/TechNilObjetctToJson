<HTML><HEAD></HEAD><BODY><!--StartFragment --><h1>TechNil.ObjToJson.Helpers</h1>
<p><strong>TechNil.ObjToJson.Helpers</strong> é uma unit Delphi que estende qualquer <code>TObject</code> com métodos genéricos de serialização e desserialização JSON, suporte a listas genéricas, objetos aninhados, streams em Base64 e mapeamento direto de <code>TDataSet</code> para objetos.</p>
<p>Ideal para quem precisa:</p>
<ul>
<li>Consumir ou expor APIs REST</li>
<li>Persistir ou carregar dados em JSON</li>
<li>Preencher objetos a partir de consultas de banco de dados</li>
</ul>
<hr />
<h2>✨ Recursos principais</h2>
<h3>Conversão JSON ↔ Objeto</h3>
<ul>
<li><strong>LoadFromJsonString</strong>: carrega de <code>string</code> (objeto ou array)</li>
<li><strong>LoadFromJSON</strong>: carrega de <code>TJSONObject</code></li>
<li><strong>LoadFromJsonArray</strong>: carrega de <code>TJSONArray</code> para <code>TObjectList&lt;T&gt;</code> ou mapeia propriedades por ordem alfabética</li>
<li><strong>ToJsonObject</strong>: converte objeto em <code>TJSONObject</code></li>
<li><strong>ToJsonArray</strong>: converte <code>TObjectList&lt;T&gt;</code> em <code>TJSONArray</code></li>
<li><strong>ToJsonString</strong>: retorna JSON como <code>string</code></li>
</ul>
<h3>Suporte avançado</h3>
<ul>
<li><strong>Listas genéricas</strong> (<code>TObjectList&lt;T&gt;</code>, <code>TList&lt;T&gt;</code>) são tratadas automaticamente</li>
<li><strong>Objetos aninhados</strong> carregados/gerados recursivamente</li>
<li><strong>Streams</strong> (<code>TStream</code>, <code>TMemoryStream</code>) convertidos para Base64 e vice-versa</li>
<li><strong>TDateTime</strong> serializado em ISO 8601, com opção UTC</li>
<li><strong>Mapeamento case-insensitive</strong> das propriedades</li>
<li><strong>Formatação de nomes</strong> via <code>TJsonHelpersOptions</code> (camelCase, lowercase, UPPERCASE…)</li>
<li><strong>MapDatasetToObject</strong>: preenche qualquer objeto a partir de um <code>TDataSet</code>, com opção de ignorar campos</li>
</ul>
<hr />
<h2>📦 Instalação</h2>
<ol>
<li>Copie <code>TechNil.ObjToJson.Helpers.pas</code> para a pasta de código-fonte do seu projeto.</li>
<li>Certifique-se de que o <em>Library Path</em> do Delphi inclua essa pasta.</li>
<li>Adicione na cláusula <code>uses</code>:
<pre><code class="language-pascal">uses
  TechNil.ObjToJson.Helpers;
</code></pre>
</li>
</ol>
<hr />
<h2>⚙️ Personalização com <code>TJsonHelpersOptions</code></h2>
<p>Use <code>TJsonHelpersOptions</code> para ajustar formatação de nomes e UTC de datas:</p>
<pre><code class="language-pascal">type
  TpCase = (tpcNone, tpcFirstWordLower, tpcLower, tpcUpper);

  TJsonHelpersOptions = class
  public
    isUTC: Boolean;      // converte TDateTime para UTC se True
    CaseFormat: TpCase;  // formata nome de propriedades
    constructor Create;
    function FormatNameProp(aName: string): string;
    function GetUTC: Boolean;
  end;
</code></pre>

CaseFormat | Exemplo
-- | --
tpcNone | NomePropriedade
tpcFirstWordLower | nomePropriedade
tpcLower | nomepropriedade
tpcUpper | NOMEPROPRIEDADE


<pre><code class="language-pascal">var
  Opts: TJsonHelpersOptions;
  Obj: TCliente;
begin
  Opts := TJsonHelpersOptions.Create;
  Opts.CaseFormat := tpcFirstWordLower;
  Opts.isUTC := True;

  Obj := TCliente.Create;
  try
    Obj.LoadFromJsonString(JsonText, Opts);
    JsonText := Obj.ToJsonString(Opts);
  finally
    Obj.Free;
    Opts.Free;
  end;
end;
</code></pre>
<hr />
<h2>🚀 Exemplos de uso</h2>
<h3>Serialização de objeto</h3>
<pre><code class="language-pascal">type
  TPedido = class
    property Codigo: Integer;
  end;

  TCliente = class
    property Id: Integer;
    property Nome: string;
    property Pedidos: TObjectList&lt;TPedido&gt;;
  end;

var
  C: TCliente;
  JsonOut: string;
begin
  C := TCliente.Create;
  try
    C.Id := 1;
    C.Nome := 'João';
    C.Pedidos := TObjectList&lt;TPedido&gt;.Create;
    C.Pedidos.Add(TPedido.Create(Codigo := 100));

    JsonOut := C.ToJsonString;
    // → {&quot;Id&quot;:1,&quot;Nome&quot;:&quot;João&quot;,&quot;Pedidos&quot;:[{&quot;Codigo&quot;:100}]}
  finally
    C.Free;
  end;
end;
</code></pre>
<h3>Desserialização de JSON</h3>
<pre><code class="language-pascal">var
  C: TCliente;
  JsonIn: string;
begin
  JsonIn := '{&quot;Id&quot;:2,&quot;Nome&quot;:&quot;Maria&quot;,&quot;Pedidos&quot;:[{&quot;Codigo&quot;:200}]}';
  C := TCliente.Create;
  try
    C.LoadFromJsonString(JsonIn);
    // C.Id = 2, C.Nome = 'Maria', C.Pedidos[0].Codigo = 200
  finally
    C.Free;
  end;
end;
</code></pre>
<h3>Mapear <code>TDataSet</code> para objeto</h3>
<pre><code class="language-pascal">var
  Q: TFDQuery;
  Cliente: TCliente;
begin
  Q.SQL.Text := 'SELECT Id, Nome FROM Clientes';
  Q.Open;
  Cliente := TCliente.Create;
  try
    Cliente.LoadFromDataSet(Q, ['CreatedAt']);
    // preenche Cliente.Id e Cliente.Nome, ignorando 'CreatedAt'
  finally
    Cliente.Free;
    Q.Close;
  end;
end;
</code></pre>
<hr />
<h2>🧠 Considerações</h2>
<ul>
<li>Apenas propriedades <strong>public/published</strong> são consideradas</li>
<li>Campos BLOB mapeados em <code>TStream</code> se a propriedade herdar de <code>TStream</code></li>
<li>Arrays JSON no contexto de lista: só converte <code>TObjectList&lt;T&gt;</code></li>
<li>Outros tipos podem ser estendidos conforme necessidade</li>
</ul>
<hr />
<h2>📄 Licença</h2>
<p>Este projeto está sob a licença <strong>MIT</strong>. Sinta-se à vontade para usar, modificar e distribuir livremente.</p>
<!--EndFragment --></BODY></HTML>
