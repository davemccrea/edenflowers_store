defmodule EdenflowersWeb.Marketing.SitemapController do
  @moduledoc """
  Generates the public sitemap for search engines.
  """

  use EdenflowersWeb, :controller

  alias Edenflowers.Catalog
  alias Edenflowers.Courses

  def index(conn, _params) do
    pages = [
      alternates("/#{language}"),
      alternates("/#{language}/weddings"),
      alternates("/#{language}/condolences"),
      alternates("/#{language}/about"),
      alternates("/#{language}/contact"),
      alternates("/#{language}/faq"),
      alternates("/#{language}/terms"),
      alternates("/#{language}/courses")
    ]

    categories = for category <- Catalog.list_categories!(), do: alternates("/#{language}/store/#{category.slug}")
    products = for product <- Catalog.list_store_products!(), do: alternates("/#{language}/product/#{product.id}")
    courses = for course <- Courses.list_upcoming_courses!(), do: alternates("/#{language}/courses/#{course.id}")

    urls =
      for alternates <- pages ++ categories ++ products ++ courses,
          {_code, path} <- alternates,
          do: "<url><loc>#{unverified_url(conn, path)}</loc></url>"

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, [
      ~s(<?xml version="1.0" encoding="UTF-8"?>),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">),
      urls,
      "</urlset>"
    ])
  end
end
