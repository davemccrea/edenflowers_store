defmodule Mix.Tasks.PassItOnCards do
  @moduledoc """
  Renders the print shop PDF of pass-it-on cards for a batch of codes, one
  code per line in `codes_file`.

  The codes are made on production, where they'll be used, and the PDF is
  rendered locally. `just print-cards "Skicka vidare 2026-11" 100` does both
  (after `just backup`) and writes `tmp/cards-skicka-vidare-2026-11.pdf`
  for the print shop. Run this task by hand only to re-render a batch from its
  saved codes file, e.g. `tmp/codes-skicka-vidare-2026-11.txt`.

  Before the first print run, Jennie approves the card's wording in
  `priv/receipts/pass-it-on.typ`. Open the PDF and check a card or two before
  sending it.

  Print shops (MEB's specs, for one) want CMYK in the PSO Coated v3
  (FOGRA51) profile and text converted to outlines, which Typst can't
  produce, so Ghostscript (`gs`) converts the rendered PDF. The profile is
  ECI's PSOcoated_v3.icc, which may be used but not redistributed, so it's
  gitignored at `priv/receipts/icc/PSOcoated_v3.icc`: download
  pso-coated_v3.zip from https://eci.org (Downloads) in a browser and unzip it
  there.
  """
  use Mix.Task

  @shortdoc "Render pass-it-on cards for a batch of codes"

  @profile "priv/receipts/icc/PSOcoated_v3.icc"

  # This URL is printed on physical cards. Keep it working even if the site's
  # other routes change, because cards already in circulation cannot be updated.
  @landing_url "https://edenflowers.fi/pass-it-on"

  @impl Mix.Task
  def run([codes_file, out]) do
    if !File.exists?(@profile), do: Mix.raise("No print profile at #{@profile}. See `mix help pass_it_on_cards`.")

    Mix.Task.run("app.config")

    codes = codes_file |> File.read!() |> String.split()
    if codes == [], do: Mix.raise("No codes in #{codes_file}")

    rgb = Path.join(System.tmp_dir!(), "pass-it-on-rgb.pdf")

    cards = Enum.map(codes, &%{code: &1, url: url(&1)})

    case Edenflowers.Typst.render("pass-it-on-main.typ", "cards", %{cards: cards}) do
      {:ok, pdf} -> File.write!(rgb, pdf)
      {:error, error} -> Mix.raise("Rendering failed: #{inspect(error)}")
    end

    to_print_ready(rgb, out)
    File.rm!(rgb)
    Mix.shell().info("#{length(codes)} cards, #{2 * length(codes)} pages: #{out}")
  end

  def run(_), do: Mix.raise("Usage: mix pass_it_on_cards CODES_FILE OUT_PDF")

  defp url(code) do
    query = URI.encode_query(code: code, utm_source: "card", utm_medium: "print", utm_campaign: "pass-it-on")
    @landing_url <> "?" <> query
  end

  defp to_print_ready(source, out) do
    profile = Path.expand(@profile)

    # Ghostscript's -dSAFER restricts file access. Explicitly allow it to read our
    # external colour profile without disabling those protections.
    args =
      ["-q", "-dSAFER", "-dBATCH", "-dNOPAUSE", "-sDEVICE=pdfwrite", "-dNoOutputFonts"] ++
        ["-sColorConversionStrategy=CMYK", "-sProcessColorModel=DeviceCMYK"] ++
        ["--permit-file-read=#{profile}", "-sOutputICCProfile=#{profile}", "-o", out, source]

    case System.cmd("gs", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, status} -> Mix.raise("Ghostscript failed (#{status}): #{output}")
    end
  rescue
    ErlangError -> Mix.raise("Ghostscript (gs) isn't installed: brew install ghostscript")
  end
end
