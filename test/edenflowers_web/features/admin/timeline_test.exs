defmodule EdenflowersWeb.Admin.TimelineTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias EdenflowersWeb.Admin.Components

  test "groups history by Helsinki day and shows each date once with local event times" do
    entries =
      [
        {"late", ~U[2020-10-31 22:30:00Z]},
        {"midnight", ~U[2020-10-31 22:00:00Z]},
        {"earlier", ~U[2020-10-31 21:30:00Z]}
      ]
      |> Enum.map(fn {id, at} -> %{id: id, at: at, title: id, details: []} end)

    html = render_component(&Components.history_timeline/1, id: "history", entries: entries, locale: "en-GB")
    document = LazyHTML.from_fragment(html)

    headings = document |> LazyHTML.query("h3") |> LazyHTML.to_tree()
    assert length(headings) == 2
    assert length(document |> LazyHTML.query("#history > li[id^=history-entry-]") |> LazyHTML.to_tree()) == 3
    assert document |> LazyHTML.query("#history-date-2020-11-01") |> LazyHTML.text() |> String.trim() == "1.11.2020"
    assert document |> LazyHTML.query("#history-date-2020-10-31") |> LazyHTML.text() |> String.trim() == "31.10.2020"

    assert document |> LazyHTML.query("time") |> Enum.map(&(LazyHTML.text(&1) |> String.trim())) == [
             "00:30",
             "00:00",
             "23:30"
           ]

    assert document |> LazyHTML.query("time") |> LazyHTML.attribute("datetime") ==
             Enum.map(entries, &DateTime.to_iso8601(&1.at))

    assert length(document |> LazyHTML.query("time") |> LazyHTML.attribute("title")) == 3
  end
end
