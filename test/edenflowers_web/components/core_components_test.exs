defmodule EdenflowersWeb.CoreComponentsTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EdenflowersWeb.CoreComponents

  defp image(overrides) do
    render_component(
      &CoreComponents.image/1,
      Keyword.merge([src: "local:///p.jpg", alt: "", width: 600, height: 750], overrides)
    )
  end

  test "emits 1x, 1.5x, and 2x variants as webp and original" do
    html = image([])

    assert html =~ ~s(type="image/webp")

    for width <- [600, 900, 1200] do
      assert html =~ "rs:fill:#{width}:#{round(width * 1.25)}:false"
    end
  end

  test "skips the 1.5x variant below 320 CSS pixels" do
    html = image(width: 24, height: 24)

    assert html =~ "rs:fill:24:24:false"
    assert html =~ "rs:fill:48:48:false"
    refute html =~ "rs:fill:36:36:false"
  end

  test "art-directed sources precede the base source and use their own crop" do
    html = image(sources: [%{media: "(min-width: 640px)", width: 600, height: 600}])

    assert html =~ ~s|media="(min-width: 640px)"|

    {art_directed_at, _} = :binary.match(html, "rs:fill:600:600:false")
    {base_at, _} = :binary.match(html, "rs:fill:600:750:false")
    assert art_directed_at < base_at
  end

  test "svgs and external urls bypass the picture element" do
    refute image(src: "local:///logo.svg", width: 160, height: 80) =~ "<picture"

    html = image(src: "https://placehold.co/400x400", width: 400, height: 400)
    refute html =~ "<picture"
    assert html =~ ~s(src="https://placehold.co/400x400")
  end

  test "priority images are eager LCP candidates" do
    assert image(priority: true) =~ ~s(fetchpriority="high")
    assert image([]) =~ ~s(loading="lazy")
  end
end
