defmodule Edenflowers.PinsTest do
  @moduledoc """
  Values the repo repeats in more than one file, checked so they can't drift
  apart silently: the Typst version, and the locale lists.
  """

  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  describe "Typst" do
    test "the Dockerfile, CI and install-typst.sh pin the same version" do
      versions =
        Map.new(["Dockerfile", ".github/workflows/ci.yml", "scripts/install-typst.sh"], fn file ->
          {file, pinned_version!(file)}
        end)

      assert versions |> Map.values() |> Enum.uniq() |> length() == 1,
             "TYPST_VERSION differs: #{inspect(versions)}. Bump all three together."
    end

    defp pinned_version!(file) do
      case Regex.scan(~r/TYPST_VERSION[=:]\s*"?(\d+\.\d+\.\d+)/, File.read!(Path.join(@root, file))) do
        [[_, version]] -> version
        matches -> flunk("#{file}: expected one TYPST_VERSION pin, found #{inspect(matches)}")
      end
    end
  end

  describe "locales" do
    test "Localize knows the same set as Edenflowers.Locales" do
      assert Application.fetch_env!(:localize, :supported_locales) |> Enum.sort() ==
               Edenflowers.Locales.all() |> Enum.sort()
    end

    # Gettext catalogs are per language; the app locale carries the region.
    test "Gettext knows every app locale's language" do
      assert Enum.sort(Gettext.known_locales(EdenflowersWeb.Gettext)) ==
               Edenflowers.Locales.all() |> Enum.map(&language/1) |> Enum.sort()
    end

    test "every app locale has the catalogs its pages need" do
      for domain <- ~w(storefront emails receipts shared admin cinder errors routes),
          locale <- Edenflowers.TranslationCatalogues.locales(domain) do
        path = Path.join(@root, "priv/gettext/#{locale}/LC_MESSAGES/#{domain}.po")
        assert File.exists?(path), "missing #{domain}.po for #{locale}"
      end
    end

    test "Finnish catalogues are reserved for customer-facing domains" do
      for domain <- ~w(admin cinder) do
        refute File.exists?(Path.join(@root, "priv/gettext/fi/LC_MESSAGES/#{domain}.po"))
      end
    end

    defp language(locale), do: locale |> String.split("-") |> hd()
  end
end
