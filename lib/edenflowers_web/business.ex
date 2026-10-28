defmodule EdenflowersWeb.Business do
  @moduledoc """
  The shop's contact details and opening hours. The footer, the contact page and
  the structured data for search engines all read them here, so they can't drift.
  """
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @weekday_hours {~T[10:00:00], ~T[18:00:00]}
  @saturday_hours {~T[10:00:00], ~T[15:00:00]}

  def business_id, do: "2944459-6"

  @doc "The address registered with the Business ID, which isn't the shop's."
  def registered_address, do: ~t"Stadsgatan 3, 65300 Vasa"
  def email, do: "info@edenflowers.fi"
  def phone, do: "+358402209494"
  def phone_display, do: "040 220 9494"
  def street_address, do: ~t"Myrvägen 1"
  def postal_town, do: ~t"65230 Vasa"
  def maps_url, do: "https://www.google.com/maps/search/?api=1&query=Minimossen%2C+Myrv%C3%A4gen+1%2C+65230+Vasa"
  def social_urls, do: ["https://www.instagram.com/edenflowers.fi/", "https://www.facebook.com/edenflowers.fi/"]

  def opening_hours_lines do
    weekdays = hours(@weekday_hours)
    saturday = hours(@saturday_hours)
    [~t"Mon–Fri: #{weekdays}", ~t"Sat: #{saturday}", ~t"Sun: closed"]
  end

  @doc """
  schema.org `WebSite` for the home page. Google takes the site name in search
  results from it; without it, Google shows the domain as "Edenflowers".
  """
  def website do
    %{
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "name" => "Eden Flowers",
      "alternateName" => "edenflowers.fi",
      "url" => EdenflowersWeb.Endpoint.url() <> "/"
    }
  end

  @doc "schema.org `Florist` facts, for the home and contact pages."
  def florist do
    %{
      "@context" => "https://schema.org",
      "@type" => "Florist",
      "name" => "Eden Flowers",
      "url" => EdenflowersWeb.Endpoint.url(),
      "logo" => EdenflowersWeb.Endpoint.url() <> "/web-app-manifest-512x512.png",
      "image" => EdenflowersWeb.CoreComponents.image_url("local:///jennie_1.jpg", 1200, 1200),
      "email" => email(),
      "telephone" => phone(),
      "address" => %{
        "@type" => "PostalAddress",
        "streetAddress" => street_address(),
        "postalCode" => "65230",
        "addressLocality" => "Vaasa",
        "addressCountry" => "FI"
      },
      "geo" => %{"@type" => "GeoCoordinates", "latitude" => 63.1243512, "longitude" => 21.5974075},
      "areaServed" => [%{"@type" => "City", "name" => "Vaasa"}, %{"@type" => "City", "name" => "Korsholm"}],
      "openingHoursSpecification" => [
        opening_hours_specification(~w(Monday Tuesday Wednesday Thursday Friday), @weekday_hours),
        opening_hours_specification(~w(Saturday), @saturday_hours)
      ],
      "sameAs" => social_urls()
    }
  end

  defp opening_hours_specification(days, {opens, closes}) do
    %{
      "@type" => "OpeningHoursSpecification",
      "dayOfWeek" => days,
      "opens" => Calendar.strftime(opens, "%H:%M"),
      "closes" => Calendar.strftime(closes, "%H:%M")
    }
  end

  defp hours({opens, closes}), do: Calendar.strftime(opens, "%H:%M") <> "–" <> Calendar.strftime(closes, "%H:%M")
end
