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

  defp attribute(html, selector, name) do
    html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.attribute(name) |> List.first()
  end

  defp candidates(html) do
    html
    |> attribute("img", "srcset")
    |> String.split(", ")
    |> Enum.map(fn candidate ->
      [url, width] = String.split(candidate, " ")
      {url, width |> String.trim_trailing("w") |> String.to_integer()}
    end)
  end

  test "renders responsive WebP without a picture wrapper for a single crop" do
    html = image([])

    refute html =~ "<picture"
    refute html =~ "<source"
    assert attribute(html, "img", "src") == CoreComponents.image_url("local:///p.jpg", 600, 750)

    assert Enum.map(candidates(html), &elem(&1, 1)) == [320, 480, 600, 640, 960, 1200]

    for {url, width} <- candidates(html) do
      assert url =~ "rs:fill:#{width}:#{round(width * 1.25)}:false"
      assert url =~ "q:80"
      assert String.ends_with?(url, ".webp")
    end
  end

  test "crop is added to every candidate" do
    html = image(width: 112, height: 112, crop: "831:831:fp:0.546:0.27")

    for {url, _width} <- candidates(html) do
      assert url =~ "/c:831:831:fp:0.546:0.27/"
    end
  end

  test "small thumbnails only request widths up to twice their declared width" do
    html = image(width: 24, height: 24)

    assert Enum.map(candidates(html), &elem(&1, 1)) == [24, 48]
  end

  test "large heroes include phone-sized candidates" do
    html = image(width: 1920, height: 1080)

    assert {_, 320} = hd(candidates(html))
    assert {_, 3840} = List.last(candidates(html))
  end

  test "caps both orientations proportionally with unique width descriptors" do
    for {width, height, max_width, max_height} <- [
          {3000, 2000, 3840, 2560},
          {2000, 3000, 2560, 3840},
          {6000, 4000, 3840, 2560}
        ] do
      variants = image(width: width, height: height) |> candidates()
      widths = Enum.map(variants, &elem(&1, 1))

      assert widths == Enum.sort(Enum.uniq(widths))
      assert {url, ^max_width} = List.last(variants)
      assert url =~ "rs:fill:#{max_width}:#{max_height}:false"
    end

    assert CoreComponents.image_url("local:///p.jpg", 6000, 4000) =~ "rs:fill:3840:2560:false"
  end

  test "art-directed sources precede the base source and use their own crop" do
    html = image(sources: [%{media: "(min-width: 640px)", width: 600, height: 600}])

    assert html =~ ~s|media="(min-width: 640px)"|
    assert html |> LazyHTML.from_fragment() |> LazyHTML.query("source") |> Enum.count() == 1
    assert attribute(html, "source", "type") == "image/webp"

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

  test "external images including SVG URLs pass through both APIs unchanged" do
    for src <- ["https://example.com/photo.jpg", "https://example.com/logo.svg?version=2#logo"] do
      html = image(src: src, sources: [%{media: "(min-width: 640px)", width: 600, height: 600}])

      assert attribute(html, "img", "src") == src
      assert attribute(html, "img", "srcset") == nil
      assert attribute(html, "img", "sizes") == nil
      refute html =~ "<picture"
      assert CoreComponents.image_url(src, 600, 750) == src
    end
  end

  test "local SVGs with query strings are proxied without raster transformations" do
    src = "local:///logo.SVG?version=2"
    expected = src |> Imgproxy.new() |> to_string()
    html = image(src: src)

    assert attribute(html, "img", "src") == expected
    assert attribute(html, "img", "srcset") == nil
    assert CoreComponents.image_url(src, 600, 750) == expected
  end

  test "shared image markup preserves layout, accessibility and loading attributes" do
    for sources <- [[], [%{media: "(min-width: 640px)", width: 600, height: 600}]] do
      html =
        image(
          sources: sources,
          alt: "Bouquet",
          class: "object-cover",
          sizes: "50vw",
          priority: true,
          rest: %{"data-testid" => "photo"}
        )

      for {name, expected} <- [
            {"alt", "Bouquet"},
            {"class", "object-cover"},
            {"sizes", "50vw"},
            {"width", "600"},
            {"height", "750"},
            {"loading", "eager"},
            {"decoding", "async"},
            {"fetchpriority", "high"},
            {"data-testid", "photo"}
          ] do
        assert attribute(html, "img", name) == expected
      end
    end
  end

  test "priority images are eager LCP candidates" do
    assert image(priority: true) =~ ~s(fetchpriority="high")
    assert image([]) =~ ~s(loading="lazy")
  end

  # A bare `aria-invalid` reads as "false" to assistive tech, and the CSS that
  # turns the focus ring red matches on the explicit value.
  test "invalid inputs carry an explicit aria-invalid value" do
    for type <- ~w(text select textarea) do
      html =
        render_component(&CoreComponents.input/1,
          type: type,
          name: "f",
          id: "f",
          value: "",
          options: [],
          errors: ["is required"]
        )

      assert attribute(html, "[aria-invalid]", "aria-invalid") == "true"
    end

    html = render_component(&CoreComponents.input/1, type: "text", name: "f", id: "f", value: "", errors: [])
    refute html =~ "aria-invalid"
  end
end
