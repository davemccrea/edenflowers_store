defmodule Edenflowers.Typst do
  @moduledoc """
  Renders the PDFs in `priv/receipts` (receipts and invoices) with the Typst
  CLI. Fonts and Typst packages are vendored there, so rendering never
  reaches the network: in tests, CI or the release image.
  """

  @typst_bin "typst"

  @doc """
  Compiles `entry` (a .typ file in priv/receipts) with `payload` as JSON in the input named `input`.
  A PDF unless `format: "png"`, which renders the first page at `ppi` (default 96).
  """
  def render(entry, input, payload, opts \\ []) do
    format = Keyword.get(opts, :format, "pdf")
    dir = Path.join(:code.priv_dir(:edenflowers), "receipts")

    args =
      [
        "compile",
        Path.join(dir, entry),
        "-",
        "--format",
        format,
        "--font-path",
        Path.join(dir, "fonts"),
        "--package-path",
        Path.join(dir, "packages"),
        "--input",
        input <> "=" <> Jason.encode!(payload)
      ] ++ if(format == "png", do: ["--pages", "1", "--ppi", to_string(Keyword.get(opts, :ppi, 96))], else: [])

    # Keep stderr separate: merging it would corrupt the PDF bytes on stdout.
    case System.cmd(@typst_bin, args) do
      {pdf, 0} -> {:ok, pdf}
      {output, status} -> {:error, {:typst_failed, status, output}}
    end
  end
end
