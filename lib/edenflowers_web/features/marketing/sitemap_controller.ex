defmodule EdenflowersWeb.Marketing.SitemapController do
  use EdenflowersWeb, :controller

  alias Edenflowers.Catalog
  alias Edenflowers.Courses

  def index(conn, _params) do
    pages = [~p"/", ~p"/weddings", ~p"/condolences", ~p"/about", ~p"/contact", ~p"/faq", ~p"/courses"]
    categories = Enum.map(Catalog.list_categories!(), &~p"/store/#{&1.slug}")
    products = Enum.map(Catalog.list_store_products!(), &~p"/product/#{&1.id}")
    courses = Enum.map(Courses.list_upcoming_courses!(), &~p"/courses/#{&1.id}")

    urls = Enum.map(pages ++ categories ++ products ++ courses, &"<url><loc>#{unverified_url(conn, &1)}</loc></url>")

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
