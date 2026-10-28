defmodule EdenflowersWeb.Review.NoteControllerTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator

  alias Edenflowers.Actors
  alias Edenflowers.Feedback

  @note %{
    "body" => "Make this headline shorter",
    "path" => "/en/about?x=1",
    "locale" => "en-GB",
    "viewport" => "1440x900",
    "selector" => "#main-content > h1",
    "element_text" => "About us",
    "element_html" => "<h1>About us</h1>"
  }

  defp signed_in_user(opts \\ []), do: admin_user(opts) |> generate() |> with_token()

  defp open_notes, do: Feedback.list_open_notes!(actor: Actors.system_actor())

  test "a reviewer's note is saved with them as author and the running version", %{conn: conn} do
    reviewer = signed_in_user(admin: false, reviewer: true)

    conn = conn |> log_in(reviewer) |> post("/review-notes", @note)

    assert response(conn, 201)
    assert [note] = open_notes()
    assert note.author_id == reviewer.id
    assert note.body == "Make this headline shorter"
    assert note.app_version =~ ~r/^v\d/
  end

  test "an admin counts as a reviewer", %{conn: conn} do
    conn = conn |> log_in(signed_in_user()) |> post("/review-notes", @note)

    assert response(conn, 201)
  end

  test "anyone else is turned away", %{conn: conn} do
    customer = signed_in_user(admin: false)

    assert conn |> log_in(customer) |> post("/review-notes", @note) |> response(403)
    assert build_conn() |> post("/review-notes", @note) |> response(403)
    assert open_notes() == []
  end

  test "only reviewers get the picker attribute on pages", %{conn: conn} do
    reviewer = signed_in_user(admin: false, reviewer: true)

    assert conn |> log_in(reviewer) |> get("/en/about") |> html_response(200) =~ "data-reviewer"
    refute build_conn() |> get("/en/about") |> html_response(200) =~ "data-reviewer"
  end

  test "the strings lookup finds the message behind translated text, in every locale", %{conn: conn} do
    conn =
      conn
      |> log_in(signed_in_user(admin: false, reviewer: true))
      |> post("/review-notes/strings", %{"texts" => ["Lisää ostoskoriin"], "locale" => "fi"})

    assert [%{"domain" => "storefront", "msgid" => "Add to cart", "translations" => translations}] =
             json_response(conn, 200)

    assert translations["en"] == "Add to cart"
    assert translations["sv"] == "Lägg i varukorgen"
    assert build_conn() |> post("/review-notes/strings", %{"texts" => ["x"], "locale" => "fi"}) |> response(403)
  end

  test "a note keeps its strings, and the page's open notes list it", %{conn: conn} do
    conn = log_in(conn, signed_in_user(admin: false, reviewer: true))
    string = %{"domain" => "storefront", "msgctxt" => nil, "msgid" => "About us"}
    post(conn, "/review-notes", Map.put(@note, "strings", [string]))

    assert Feedback.open_notes_markdown() =~ ~s(- String: storefront.po msgid "About us")

    assert [%{"body" => "Make this headline shorter", "selector" => "#main-content > h1"}] =
             conn |> get("/review-notes", %{"path" => "/en/about?x=1"}) |> json_response(200)

    assert [] = conn |> get("/review-notes", %{"path" => "/en/other"}) |> json_response(200)
    assert [] = build_conn() |> get("/review-notes", %{"path" => "/en/about?x=1"}) |> json_response(200)
  end

  test "only a note's author can rewrite it", %{conn: conn} do
    author = signed_in_user(admin: false, reviewer: true)
    other = signed_in_user(admin: false, reviewer: true)
    conn |> log_in(author) |> post("/review-notes", @note)
    [note] = open_notes()

    assert build_conn() |> log_in(other) |> patch("/review-notes/#{note.id}", %{"body" => "Mine now"}) |> response(403)
    assert build_conn() |> log_in(author) |> patch("/review-notes/#{note.id}", %{"body" => "Shorter"}) |> response(204)
    assert [%{body: "Shorter"}] = open_notes()

    assert [%{"mine?" => true}] =
             build_conn() |> log_in(author) |> get("/review-notes", %{"path" => @note["path"]}) |> json_response(200)
  end

  test "only a note's author can delete it", %{conn: conn} do
    author = signed_in_user(admin: false, reviewer: true)
    other = signed_in_user(admin: false, reviewer: true)
    conn |> log_in(author) |> post("/review-notes", @note)
    [note] = open_notes()

    assert build_conn() |> log_in(other) |> delete("/review-notes/#{note.id}") |> response(403)
    assert [_note] = open_notes()

    assert build_conn() |> log_in(author) |> delete("/review-notes/#{note.id}") |> response(204)
    assert open_notes() == []
  end

  test "resolved notes drop out of the open list and its Markdown", %{conn: conn} do
    conn |> log_in(signed_in_user(admin: false, reviewer: true)) |> post("/review-notes", @note)
    [note] = open_notes()

    assert Feedback.open_notes_markdown() =~ "Make this headline shorter"

    Feedback.resolve_note!(note.number, actor: Actors.system_actor())

    assert open_notes() == []
    assert Feedback.open_notes_markdown() == "No open review notes."
  end
end
