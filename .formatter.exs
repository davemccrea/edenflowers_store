[
  import_deps: [:ash_postgres, :ash, :ecto, :ecto_sql, :phoenix, :ash_archival],
  subdirectories: ["priv/*/migrations"],
  plugins: [Spark.Formatter, Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"],
  line_length: 120
]
