%{
  configs: [
    %{
      name: "default",
      files: %{included: ["lib/", "test/"], excluded: []},
      strict: true,
      checks: %{
        enabled: [
          {Credo.Check.Readability.StrictModuleLayout,
           order: [:moduledoc, :behaviour, :use, :require, :import, :alias, :shortdoc, :module_attribute]},
          {Credo.Check.Readability.AliasOrder, []},
          {Credo.Check.Readability.MultiAlias, []},
          {Credo.Check.Consistency.MultiAliasImportRequireUse, []},
          {Credo.Check.Design.AliasUsage, if_nested_deeper_than: 2, if_called_more_often_than: 1}
        ]
      }
    }
  ]
}
