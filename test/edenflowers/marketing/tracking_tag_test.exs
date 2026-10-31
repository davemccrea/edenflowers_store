defmodule Edenflowers.Marketing.TrackingTagTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Marketing

  setup do
    %{admin: generate(admin_user())}
  end

  test "using a tag again moves it to the top instead of adding a second", %{admin: admin} do
    Marketing.use_tracking_tag!(:source, "instagram", actor: admin)
    Marketing.use_tracking_tag!(:source, "newsletter", actor: admin)
    Marketing.use_tracking_tag!(:source, " Instagram ", actor: admin)

    assert [{:source, "instagram"}, {:source, "newsletter"}] ==
             Marketing.recent_tracking_tags!(actor: admin) |> Enum.map(&{&1.parameter, &1.value})
  end

  test "a copied link's tags are remembered normalised, skipping empty ones", %{admin: admin} do
    Marketing.use_tracking_tags!(%{source: "Instagram", medium: "", campaign: "Mothers  Day 2026"}, actor: admin)

    assert [{:campaign, "mothers-day-2026"}, {:source, "instagram"}] ==
             Marketing.recent_tracking_tags!(actor: admin) |> Enum.map(&{&1.parameter, &1.value}) |> Enum.sort()
  end

  test "suggestions are the most recent tags per parameter, six at most", %{admin: admin} do
    Marketing.use_tracking_tags!(%{source: "facebook", campaign: "wedding-fair"}, actor: admin)
    Marketing.use_tracking_tags!(%{source: "flyer"}, actor: admin)

    assert %{source: ~w(flyer facebook), medium: [], campaign: ~w(wedding-fair)} ==
             Marketing.tracking_tag_suggestions!(actor: admin)

    for value <- ~w(a b c d e f g), do: Marketing.use_tracking_tag!(:campaign, value, actor: admin)
    assert Marketing.tracking_tag_suggestions!(actor: admin).campaign == ~w(g f e d c b)
  end

  test "a forgotten tag is no longer suggested", %{admin: admin} do
    Marketing.use_tracking_tags!(%{source: "instgram"}, actor: admin)
    Marketing.use_tracking_tags!(%{source: "instagram"}, actor: admin)

    Marketing.forget_tracking_tag!(:source, "instgram", actor: admin)

    assert Marketing.tracking_tag_suggestions!(actor: admin).source == ~w(instagram)
  end

  test "a tagged URL carries only the tags with a value, normalised", %{admin: admin} do
    tags = %{source: "Instagram", medium: " ", campaign: "Autumn courses"}

    assert "https://edenflowers.fi/courses?utm_source=instagram&utm_campaign=autumn-courses" ==
             Marketing.tagged_url!("https://edenflowers.fi/courses", tags, actor: admin)

    assert "https://edenflowers.fi/courses" ==
             Marketing.tagged_url!("https://edenflowers.fi/courses", %{}, actor: admin)
  end

  test "only admins can use or see tags", %{admin: admin} do
    user = generate(admin_user(admin: false))
    Marketing.use_tracking_tag!(:source, "instagram", actor: admin)

    assert {:error, %Ash.Error.Forbidden{}} = Marketing.use_tracking_tag(:source, "facebook", actor: user)
    assert {:error, %Ash.Error.Forbidden{}} = Marketing.tracking_tag_suggestions(actor: user)
    assert [] == Marketing.recent_tracking_tags!(actor: user)
  end
end
