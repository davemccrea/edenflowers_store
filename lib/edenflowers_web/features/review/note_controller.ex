defmodule EdenflowersWeb.Review.NoteController do
  @moduledoc """
  Saves a review note posted by the Option+Click picker (`assets/js/element_picker.js`).
  A plain JSON endpoint rather than a LiveView event, so notes work on controller
  pages such as receipts too.
  """
  use EdenflowersWeb, :controller

  def create(conn, params) do
    case Edenflowers.Feedback.leave_note(params, actor: conn.assigns[:current_user]) do
      {:ok, _note} -> send_resp(conn, 201, "")
      {:error, %Ash.Error.Forbidden{}} -> send_resp(conn, 403, "")
      {:error, _invalid} -> send_resp(conn, 422, "")
    end
  end
end
