defmodule EdenflowersWeb.Marketing.SitemapController do
  use EdenflowersWeb, :controller

  alias Edenflowers.Catalog
  alias Edenflowers.Courses
  alias EdenflowersWeb.LocalizedPaths

  def index(conn, _params) do
    pages = [
      ~p"/en",
      ~p"/en/weddings",
      ~p"/en/condolences",
      ~p"/en/about",
      ~p"/en/contact",
      ~p"/en/faq",
      ~p"/en/courses"
    ]

    categories = Enum.map(Catalog.list_categories!(), &~p"/en/store/#{&1.slug}")
    products = Enum.map(Catalog.list_store_products!(), &~p"/en/product/#{&1.id}")
    courses = Enum.map(Courses.list_upcoming_courses!(), &~p"/en/courses/#{&1.id}")

    urls =
      for page <- pages ++ categories ++ products ++ courses,
          {_hreflang, path} <- LocalizedPaths.alternates(page),
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
