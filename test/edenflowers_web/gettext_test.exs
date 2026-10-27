defmodule EdenflowersWeb.GettextTest do
  use ExUnit.Case, async: true

  alias EdenflowersWeb.Gettext, as: Backend

  @root Path.expand("../..", __DIR__)
  @domains ~w(storefront emails receipts shared admin)

  test "the default domain is customer-facing and the mixed catalogue is gone" do
    assert Backend.__gettext__(:default_domain) == "storefront"
    assert Path.wildcard(Path.join(@root, "priv/gettext/**/default.{po,pot}")) == []
  end

  test "every audience catalogue matches its template in every language" do
    for domain <- @domains do
      template = catalogue("priv/gettext/#{domain}.pot")
      template_keys = MapSet.new(template.messages, &Expo.Message.key/1)

      for locale <- ~w(en sv fi) do
        messages = catalogue("priv/gettext/#{locale}/LC_MESSAGES/#{domain}.po").messages
        active = Enum.reject(messages, & &1.obsolete)
        assert MapSet.new(active, &Expo.Message.key/1) == template_keys, "#{locale}/#{domain} is stale"
      end
    end
  end

  test "admin and email source strings extract into their audience's domain" do
    for domain <- @domains,
        message <- catalogue("priv/gettext/#{domain}.pot").messages,
        {path, _line} <- List.flatten(message.references) do
      cond do
        String.starts_with?(path, "lib/edenflowers_web/features/admin/") ->
          assert domain == "admin", "#{path} extracted into #{domain}"

        String.starts_with?(path, "lib/edenflowers/email/templates") ->
          assert domain == "emails", "#{path} extracted into #{domain}"

        true ->
          :ok
      end
    end
  end

  test "translations resolve through storefront, shared, admin contexts and email templates" do
    Gettext.with_locale(Backend, "sv", fn ->
      assert Gettext.dgettext(Backend, :default, "Checkout") == "Kassa"
      assert Edenflowers.Catalog.ProductType.label(:stem_count) == "Stjälkar"
      assert EdenflowersWeb.Admin.Components.subscription_state_label(:cancelled) == "Avslutad"

      email = Edenflowers.Email.Templates.otp_sign_in(%{otp_code: "123456"})
      assert email =~ "Här är din inloggningskod till Eden Flowers:"
      assert email =~ "123456"
    end)
  end

  test "the cart's dynamic item count has extractable plural translations" do
    for {locale, one, many} <- [
          {"sv", "Varukorg, 1 vara", "Varukorg, 2 varor"},
          {"fi", "Ostoskori, 1 tuote", "Ostoskori, 2 tuotetta"}
        ] do
      Gettext.with_locale(Backend, locale, fn ->
        assert Gettext.dngettext(Backend, "storefront", "Cart, %{count} item", "Cart, %{count} items", 1) == one
        assert Gettext.dngettext(Backend, "storefront", "Cart, %{count} item", "Cart, %{count} items", 2) == many
      end)
    end
  end

  test "translation progress reports customer-facing and deferrable work separately" do
    output = ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Gettext.Stats.run([]) end)

    assert output =~ ~r/sv\s+critical\s+storefront/
    assert output =~ ~r/fi\s+critical\s+emails/
    assert output =~ ~r/sv\s+critical\s+receipts/
    assert output =~ ~r/sv\s+can wait\s+admin/
    assert output =~ "Obsolete entries are excluded."
  end

  defp catalogue(path), do: @root |> Path.join(path) |> Expo.PO.parse_file!()
end
