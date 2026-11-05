defmodule Mix.Tasks.PassItOnCards do
  @moduledoc """
  Renders the print shop PDF of pass-it-on cards for a batch of codes, one
  code per line in `codes_file`.

  The codes are made on production, where they'll be used, and the PDF is
  rendered locally:

      ssh … rpc 'Edenflowers.Pricing.create_pass_it_on_batch!("Skicka vidare 2026-11", 100,
        actor: Edenflowers.Actors.system_actor()) |> Enum.each(&IO.puts/1)' > tmp/codes.txt
      mix pass_it_on_cards tmp/codes.txt tmp/pass-it-on.pdf

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

  @impl Mix.Task
  def run([codes_file, out]) do
    if !File.exists?(@profile), do: Mix.raise("No print profile at #{@profile}. See `mix help pass_it_on_cards`.")

    Mix.Task.run("app.config")

    codes = codes_file |> File.read!() |> String.split()
    if codes == [], do: Mix.raise("No codes in #{codes_file}")

    rgb = Path.join(System.tmp_dir!(), "pass-it-on-rgb.pdf")

    case Edenflowers.Pricing.PassItOnCards.render(codes) do
      {:ok, pdf} -> File.write!(rgb, pdf)
      {:error, error} -> Mix.raise("Rendering failed: #{inspect(error)}")
    end

    to_print_ready(rgb, out)
    File.rm!(rgb)
    Mix.shell().info("#{length(codes)} cards, #{2 * length(codes)} pages: #{out}")
  end

  def run(_), do: Mix.raise("Usage: mix pass_it_on_cards CODES_FILE OUT_PDF")

  defp to_print_ready(source, out) do
    profile = Path.expand(@profile)

    # -dSAFER only lets Ghostscript read its own files, so the profile is permitted by name.
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
