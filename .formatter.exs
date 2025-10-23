[
  import_deps: [
    :ash_authentication_phoenix,
    :ash_authentication,
    :oban,
    :ash_postgres,
    :ash,
    :ecto,
    :ecto_sql,
    :phoenix,
    :ash_archival,
    :ash_trans
  ],
  subdirectories: ["priv/*/migrations"],
  plugins: [Spark.Formatter, Phoenix.LiveView.HTMLFormatter, TailwindFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,eex,ex,exs}", "priv/*/seeds.exs"],
  line_length: 120
]
