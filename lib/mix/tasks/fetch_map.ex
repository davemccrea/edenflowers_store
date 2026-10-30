defmodule Mix.Tasks.FetchMap do
  @moduledoc """
  Fetches the Vaasa location map from Mapbox Static Images API and writes it to
  `images/home-vaasa-map-10.png`, the Imgproxy local-storage source.

  ## Why a Mix task

  The map is a fixed editorial asset: one location, one zoom, never changes per
  request. Fetching at runtime would either hit Mapbox on every cold-start
  (wasteful) or require cache invalidation logic (premature). A Mix task you
  run manually, with the resulting PNG committed to the repo, is the honest
  pattern.

  ## Usage

      MAPBOX_TOKEN=pk.… mix fetch_map

  Re-run whenever you want to refresh the asset (e.g. after Mapbox updates the
  style or you change the spec below).
  """
  use Mix.Task

  @shortdoc "Fetch the Vaasa location map from Mapbox"

  # Composition spec. Dimensions are the Mapbox source; the render aspect is
  # preserved (1097:1280 ≈ 800:940) so Imgproxy can pure-downscale to any DPR
  # without re-cropping.
  # Centred between the shop and Vaasa's market square, nearer the shop. On desktop the
  # page crops up to ~27% off the top and bottom, which would hide the pin if
  # the frame were centred on the market square itself.
  @center {21.6083, 63.1120}
  @shop {21.6000, 63.1243}
  @zoom 12.5
  @width 1097
  @height 1280
  @style "davemccrea/cmp1rbxej001201r0c0z808jo"
  # `pin-m` is Mapbox's medium built-in pin. Color is hex without `#`.
  # Honey approximates --color-link-underline.
  @marker_color "E8B33C"
  # Imgproxy caches an image for a year, so a re-styled map needs a new filename.
  @output_path "images/home-vaasa-map-10.png"

  # The custom style only has land and water, so roads are layered on at
  # request time from Mapbox's own street data, tinted to sit quietly on the
  # warm white land colour.
  @road_layer %{
    id: "roads",
    type: "line",
    source: "composite",
    "source-layer": "road",
    filter: [
      "match",
      ["get", "class"],
      ["motorway", "trunk", "primary", "secondary", "tertiary", "street", "street_limited"],
      true,
      false
    ],
    paint: %{
      "line-color": "#d2cabd",
      "line-width": [
        "match",
        ["get", "class"],
        ["motorway", "trunk", "primary"],
        2,
        ["secondary", "tertiary"],
        1.2,
        0.6
      ]
    }
  }

  @impl Mix.Task
  def run(_args) do
    token =
      System.get_env("MAPBOX_TOKEN") ||
        Mix.raise("MAPBOX_TOKEN environment variable is missing.")

    Mix.Task.run("app.start")

    url = build_url(token)
    Mix.shell().info("Fetching #{Path.basename(@output_path)} from Mapbox…")

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        File.mkdir_p!(Path.dirname(@output_path))
        File.write!(@output_path, body)
        Mix.shell().info("Wrote #{byte_size(body)} bytes to #{@output_path}")

      {:ok, %{status: status, body: body}} ->
        Mix.raise("Mapbox returned #{status}: #{inspect(body)}")

      {:error, reason} ->
        Mix.raise("Request failed: #{inspect(reason)}")
    end
  end

  defp build_url(token) do
    {center_lng, center_lat} = @center
    {shop_lng, shop_lat} = @shop

    marker = "pin-m+#{@marker_color}(#{shop_lng},#{shop_lat})"
    coords = "#{center_lng},#{center_lat},#{@zoom}"
    size = "#{@width}x#{@height}@2x"

    "https://api.mapbox.com/styles/v1/#{@style}/static/" <>
      "#{marker}/#{coords}/#{size}" <>
      "?" <>
      URI.encode_query(
        access_token: token,
        logo: false,
        attribution: false,
        # Skips Mapbox's CDN, which otherwise serves a render from before a style edit.
        fresh: true,
        addlayer: JSON.encode!(@road_layer)
      )
  end
end
