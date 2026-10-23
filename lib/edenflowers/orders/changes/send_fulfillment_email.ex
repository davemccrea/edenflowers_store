defmodule Edenflowers.Orders.Changes.SendFulfillmentEmail do
  @moduledoc """
  Emails a customer when their order is delivered: Left at the door, with
  its photo, when nobody was home, else Delivered. A successful send stamps `fulfillment_emailed_at` and clears
  `fulfillment_email_failed_at`. A failed send fails the action, so the AshOban
  trigger retries it and, once attempts run out, `record_fulfillment_email_failure`
  stamps `fulfillment_email_failed_at` for the admin to see.
  """

  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &send_email/1)
  end

  defp send_email(changeset) do
    order = Ash.load!(changeset.data, [:customer_first_name, :recipient_first_name], authorize?: false)
    message = Ash.Changeset.get_argument(changeset, :message)

    case email(order, message) do
      {:ok, email} ->
        changeset
        |> Ash.Changeset.set_context(%{paper_trail_metadata: %{email_message: message}})
        |> deliver(order, email)

      {:error, error} ->
        Ash.Changeset.add_error(changeset, field: :delivery_photo_slug, message: email_error(error))
    end
  end

  defp deliver(changeset, order, email) do
    case Mailer.deliver(email) do
      {:ok, _result} ->
        Logger.info("Sent fulfillment email for order #{order.id}")

        changeset
        |> Ash.Changeset.force_change_attributes(
          fulfillment_emailed_at: DateTime.utc_now(),
          fulfillment_emailed_to: order.customer_email
        )
        |> clear_failure()

      {:error, error} ->
        Ash.Changeset.add_error(changeset, email_error(error))
    end
  end

  defp email_error(error), do: ~t"Failed to send fulfillment email: #{error = inspect(error)}"

  defp email(%{email_delivery_photo: true, delivery_photo_slug: slug} = order, message)
       when is_binary(slug) and byte_size(slug) > 0 do
    with {:ok, jpeg} <- fetch_small_photo(slug), do: {:ok, Email.order_left_at_door(order, jpeg, message)}
  end

  defp email(%{email_delivery_photo: true}, _message),
    do: {:error, ~t"Delivery photo is missing."}

  defp email(order, message), do: {:ok, Email.order_delivered(order, message)}

  # A phone photo can be 10 MB or more. 1600 px at quality 80 comes to a few
  # hundred KB: small enough for any inbox, sharp enough to spot a doorstep.
  defp fetch_small_photo(slug) do
    url =
      slug
      |> Imgproxy.new()
      |> Imgproxy.resize(1600, 1600, type: "fit")
      |> Imgproxy.add_option(:q, [80])
      |> Imgproxy.set_extension("jpg")
      |> to_string()

    case Req.get(url, Application.get_env(:edenflowers, :delivery_photo_req_options, [])) do
      {:ok, %{status: 200, body: jpeg}} -> {:ok, jpeg}
      {:ok, %{status: status}} -> {:error, "imgproxy answered #{status} for the delivery photo"}
      {:error, error} -> {:error, error}
    end
  end

  # Atomic, so a caller holding a copy from before the failure still clears it.
  defp clear_failure(changeset), do: Ash.Changeset.atomic_update(changeset, :fulfillment_email_failed_at, nil)
end
