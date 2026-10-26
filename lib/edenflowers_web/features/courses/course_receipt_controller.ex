defmodule EdenflowersWeb.Courses.CourseReceiptController do
  @moduledoc """
  Downloads the receipt PDF for a course booking.
  """

  use EdenflowersWeb, :controller

  alias Edenflowers.Courses
  alias Edenflowers.Orders.Receipt
  alias Edenflowers.Translations

  # Read as the signed-in customer, so the owner policy decides: the receipt
  # carries their email address.
  def show(conn, %{"id" => id}) do
    with {:ok, %{receipt_available?: true} = registration} <-
           Courses.get_registration_by_id(id,
             actor: conn.assigns[:current_user],
             load: [:course, :payments, :receipt_available?]
           ),
         {:ok, pdf} <- Receipt.generate(translate_course(registration)) do
      send_download(conn, {:binary, pdf},
        filename: "eden-flowers-#{registration.reference}.pdf",
        content_type: "application/pdf",
        disposition: :inline
      )
    else
      _ -> send_resp(conn, :not_found, "Not found")
    end
  end

  # The receipt reads in the language the customer booked in, like the emailed one.
  defp translate_course(registration) do
    locale = String.to_existing_atom(registration.locale)
    Map.update!(registration, :course, &Translations.translate(&1, locale))
  end
end
