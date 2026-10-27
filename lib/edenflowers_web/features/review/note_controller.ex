defmodule EdenflowersWeb.Review.NoteController do
  @moduledoc """
  Saves a review note posted by the Option+Click picker (`assets/js/element_picker.js`).
  A plain JSON endpoint rather than a LiveView event, so notes work on controller
  pages such as receipts too.
  """
  use EdenflowersWeb, :controller

  @doc "The page's open notes, so the picker can outline their elements while Option is held."
  def index(conn, %{"path" => path}) do
    case Edenflowers.Feedback.list_open_notes_on_page(path, actor: conn.assigns[:current_user]) do
      {:ok, notes} ->
        json(conn, Enum.map(notes, &Map.take(&1, [:id, :body, :selector, :element_text, :mine?])))

      {:error, _forbidden} ->
        send_resp(conn, 403, "")
    end
  end

  @doc "The Gettext messages behind the clicked element's text, with their text in every locale."
  def strings(conn, %{"texts" => texts, "locale" => locale}) do
    case Edenflowers.Feedback.find_strings(texts, locale, actor: conn.assigns[:current_user]) do
      {:ok, strings} -> json(conn, strings)
      {:error, %Ash.Error.Forbidden{}} -> send_resp(conn, 403, "")
      {:error, _invalid} -> send_resp(conn, 422, "")
    end
  end

  @doc "Rewrites a note, when its author Option+Clicks the element again."
  def update(conn, %{"id" => id, "body" => body}) do
    case Edenflowers.Feedback.edit_note(id, %{body: body}, actor: conn.assigns[:current_user]) do
      {:ok, _note} -> send_resp(conn, 204, "")
      {:error, %Ash.Error.Forbidden{}} -> send_resp(conn, 403, "")
      {:error, _invalid} -> send_resp(conn, 422, "")
    end
  end

  def create(conn, params) do
    case Edenflowers.Feedback.leave_note(params, actor: conn.assigns[:current_user]) do
      {:ok, _note} -> send_resp(conn, 201, "")
      {:error, %Ash.Error.Forbidden{}} -> send_resp(conn, 403, "")
      {:error, _invalid} -> send_resp(conn, 422, "")
    end
  end
end
