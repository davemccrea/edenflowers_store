defmodule Edenflowers.Orders.Changes.SendDeliveredEmail do
  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      order = Ash.load!(changeset.data, [:customer_first_name, :recipient_first_name], authorize?: false)

      with {:ok, email} <- email(order),
           {:ok, _result} <- Mailer.deliver(email) do
        Logger.info("Sent delivered email for order #{order.id}")
        Ash.Changeset.force_change_attribute(changeset, :delivered_emailed_at, DateTime.utc_now())
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, "Failed to send delivered email: #{inspect(error)}")
      end
    end)
  end

  defp email(%{email_delivery_photo: true, delivery_photo_slug: slug} = order) when is_binary(slug) do
    with {:ok, jpeg} <- fetch_small_photo(slug), do: {:ok, Email.order_left_at_door(order, jpeg)}
  end

  defp email(order), do: {:ok, Email.order_delivered(order)}

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
