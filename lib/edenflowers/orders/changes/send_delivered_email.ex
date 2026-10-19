defmodule Edenflowers.Orders.Changes.SendDeliveredEmail do
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Orders.Order

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      if Order.fulfillment_email_pending?(changeset.data) do
        send_email(changeset)
      else
        Ash.Changeset.set_context(changeset, %{skip_version_when_unchanged?: true})
      end
    end)
  end

  defp send_email(changeset) do
    order = Ash.load!(changeset.data, [:customer_first_name, :recipient_first_name], authorize?: false)

    with {:ok, email} <- email(order) do
      case Mailer.deliver(email) do
        {:ok, _result} ->
          Logger.info("Sent fulfillment email for order #{order.id}")

          Ash.Changeset.force_change_attributes(changeset,
            delivered_emailed_at: DateTime.utc_now(),
            delivered_emailed_to: order.customer_email
          )

        {:error, error} ->
          Ash.Changeset.add_error(changeset, email_error(error))
      end
    else
      {:error, error} ->
        Ash.Changeset.add_error(changeset, field: :delivery_photo_slug, message: email_error(error))
    end
  end

  defp email_error(error), do: ~t"Failed to send fulfillment email: #{error = inspect(error)}"

  defp email(%{fulfillment_method: :delivery, email_delivery_photo: true, delivery_photo_slug: slug} = order)
       when is_binary(slug) and byte_size(slug) > 0 do
    with {:ok, jpeg} <- fetch_small_photo(slug), do: {:ok, Email.order_left_at_door(order, jpeg)}
  end

  defp email(%{fulfillment_method: :delivery, email_delivery_photo: true}),
    do: {:error, ~t"Delivery photo is missing."}

  defp email(order), do: {:ok, Email.order_fulfilled(order)}

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
end
